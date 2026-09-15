import AppKit
import Combine
import QuartzCore

struct TrackInfo: Equatable, Sendable {
    var id: String
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
}

struct PlayerSnapshot: Sendable {
    enum State: Sendable { case playing, paused, stopped, notRunning, denied, failed }
    var state: State
    var position: TimeInterval = 0
    var track: TrackInfo?
    /// Monotonic time (CACurrentMediaTime) the position was sampled at.
    var sampledAt: CFTimeInterval
}

/// Talks to Music.app over Apple Events on a private serial queue so polling never stalls animations.
final class MusicScriptBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "NotchLyrics.AppleScript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]
    private static let bundleID = "com.apple.Music"

    private static let statusScript = """
    if application id "com.apple.Music" is running then
        with timeout of 3 seconds
            tell application id "com.apple.Music"
                set stateText to player state as text
                if stateText is "stopped" then return {"stopped"}
                set positionValue to 0
                try
                    set positionValue to player position
                end try
                set trackName to ""
                set trackArtist to ""
                set trackAlbum to ""
                set trackDuration to 0
                set trackID to ""
                try
                    set theTrack to current track
                    try
                        set trackName to name of theTrack
                    end try
                    try
                        set trackArtist to artist of theTrack
                    end try
                    try
                        set trackAlbum to album of theTrack
                    end try
                    try
                        set trackDuration to duration of theTrack
                    end try
                    try
                        set trackID to persistent ID of theTrack
                    end try
                end try
                return {stateText, positionValue, trackName, trackArtist, trackAlbum, trackDuration, trackID}
            end tell
        end timeout
    end if
    return {"notrunning"}
    """

    private static let artworkScript = """
    tell application id "com.apple.Music"
        try
            return raw data of artwork 1 of current track
        on error
            return data of artwork 1 of current track
        end try
    end tell
    """

    func snapshot(_ completion: @escaping @Sendable (PlayerSnapshot) -> Void) {
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleID).isEmpty else {
            completion(PlayerSnapshot(state: .notRunning, sampledAt: CACurrentMediaTime()))
            return
        }
        queue.async {
            let before = CACurrentMediaTime()
            let (descriptor, errorNumber) = self.execute(Self.statusScript)
            let sampledAt = (before + CACurrentMediaTime()) / 2
            completion(Self.parse(descriptor, errorNumber: errorNumber, sampledAt: sampledAt))
        }
    }

    func artwork(_ completion: @escaping @Sendable (Data?) -> Void) {
        queue.async {
            let data = self.execute(Self.artworkScript).0?.data
            completion(data?.isEmpty == false ? data : nil)
        }
    }

    func command(_ command: String, then completion: @escaping @Sendable () -> Void) {
        queue.async {
            _ = self.execute("tell application id \"com.apple.Music\" to \(command)")
            completion()
        }
    }

    /// Must only be called on `queue`.
    private func execute(_ source: String) -> (NSAppleEventDescriptor?, Int?) {
        let script: NSAppleScript
        if let cached = compiled[source] {
            script = cached
        } else {
            guard let created = NSAppleScript(source: source) else { return (nil, nil) }
            compiled[source] = created
            script = created
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            return (nil, error[NSAppleScript.errorNumber] as? Int ?? -1)
        }
        return (result, nil)
    }

    private static func parse(_ descriptor: NSAppleEventDescriptor?, errorNumber: Int?, sampledAt: CFTimeInterval) -> PlayerSnapshot {
        if let errorNumber {
            // -1743: the user denied Automation permission for Music.
            return PlayerSnapshot(state: errorNumber == -1743 ? .denied : .failed, sampledAt: sampledAt)
        }
        guard let descriptor, descriptor.numberOfItems >= 1 else {
            return PlayerSnapshot(state: .failed, sampledAt: sampledAt)
        }
        switch descriptor.atIndex(1)?.stringValue {
        case "stopped": return PlayerSnapshot(state: .stopped, sampledAt: sampledAt)
        case "notrunning": return PlayerSnapshot(state: .notRunning, sampledAt: sampledAt)
        case let state? where (state == "playing" || state == "paused") && descriptor.numberOfItems >= 7:
            let title = descriptor.atIndex(3)?.stringValue ?? ""
            let artist = descriptor.atIndex(4)?.stringValue ?? ""
            let duration = descriptor.atIndex(6)?.doubleValue ?? 0
            let persistentID = descriptor.atIndex(7)?.stringValue ?? ""
            let track = title.isEmpty ? nil : TrackInfo(
                id: persistentID.isEmpty ? "\(title)|\(artist)|\(duration)" : persistentID,
                title: title,
                artist: artist,
                album: descriptor.atIndex(5)?.stringValue ?? "",
                duration: duration)
            return PlayerSnapshot(
                state: state == "playing" ? .playing : .paused,
                position: descriptor.atIndex(2)?.doubleValue ?? 0,
                track: track,
                sampledAt: sampledAt)
        default:
            return PlayerSnapshot(state: .failed, sampledAt: sampledAt)
        }
    }
}

@MainActor
final class MusicController: ObservableObject {
    @Published private(set) var track: TrackInfo?
    @Published private(set) var isPlaying = false
    @Published private(set) var artwork: NSImage?
    @Published private(set) var automationDenied = false

    /// Thread-safe mirror of the playback anchor, for the audio sync session.
    let clock = PlaybackClock()

    private let bridge = MusicScriptBridge()
    private var anchorPosition: TimeInterval = 0
    private var anchorTime: CFTimeInterval = CACurrentMediaTime()
    private var timer: Timer?
    private var pollInFlight = false

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.Music.playerInfo"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        poll()
    }

    /// Playback position interpolated between polls using a monotonic clock.
    func position(at time: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval {
        guard isPlaying else { return anchorPosition }
        return anchorPosition + (time - anchorTime)
    }

    func playPause() { send("playpause") }
    func nextTrack() { send("next track") }
    func previousTrack() { send("previous track") }

    func poll() {
        guard !pollInFlight else { return }
        pollInFlight = true
        bridge.snapshot { [weak self] snapshot in
            Task { @MainActor in
                self?.pollInFlight = false
                self?.apply(snapshot)
            }
        }
    }

    private func send(_ command: String) {
        bridge.command(command) { [weak self] in
            Task { @MainActor in self?.poll() }
        }
    }

    private func apply(_ snapshot: PlayerSnapshot) {
        defer {
            clock.update(PlaybackClock.Anchor(trackID: track?.id, position: anchorPosition, time: anchorTime, isPlaying: isPlaying))
        }
        if (snapshot.state == .denied) != automationDenied {
            Log.music.info("automation denied: \(snapshot.state == .denied)")
        }
        automationDenied = snapshot.state == .denied

        guard snapshot.state == .playing || snapshot.state == .paused, let newTrack = snapshot.track else {
            if isPlaying { isPlaying = false }
            if snapshot.state != .failed, track != nil {
                track = nil
                artwork = nil
            }
            return
        }

        let playing = snapshot.state == .playing
        if newTrack != track {
            Log.music.info("track: \(newTrack.title, privacy: .public) — \(newTrack.artist, privacy: .public) (\(newTrack.duration)s) state=\(String(describing: snapshot.state), privacy: .public)")
            anchorPosition = snapshot.position
            anchorTime = snapshot.sampledAt
            track = newTrack
            loadArtwork(for: newTrack)
        } else if playing && isPlaying {
            let drift = snapshot.position - position(at: snapshot.sampledAt)
            if abs(drift) > 0.4 {
                // A seek, or we fell far behind: jump.
                anchorPosition = snapshot.position
                anchorTime = snapshot.sampledAt
            } else {
                // Small jitter from Apple Event latency: ease toward the reported value.
                anchorPosition += drift * 0.35
            }
        } else {
            anchorPosition = snapshot.position
            anchorTime = snapshot.sampledAt
        }
        if isPlaying != playing { isPlaying = playing }
    }

    private func loadArtwork(for track: TrackInfo) {
        artwork = nil
        bridge.artwork { [weak self] data in
            Task { @MainActor in
                guard let self, self.track?.id == track.id else { return }
                self.artwork = data.flatMap(NSImage.init(data:))
            }
        }
    }
}
