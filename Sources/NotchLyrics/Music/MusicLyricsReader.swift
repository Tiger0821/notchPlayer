import AppKit
import ApplicationServices
import Combine
import LyricsCore

/// Reads the lyrics out of Music's own lyrics pane. Apple exposes each line as an accessible element and marks
/// the one being sung, so the line timing is Apple's own — which is what the online sources most often get
/// wrong, and what auto-sync otherwise has to recover by listening. Apple doesn't expose per-word timing, so
/// the fill inside a line is estimated.
@MainActor
final class MusicLyricsReader: ObservableObject {
    /// The `Lyrics.source` these carry, so the rest of the app can tell they are already aligned.
    nonisolated static let sourceName = "Apple Music"

    enum Status: Equatable {
        case off
        case needsPermission
        /// Music is running but its lyrics pane isn't on screen to read.
        case needsLyricsPane
        case reading(lines: Int)
    }

    @Published private(set) var lyrics: Lyrics?
    /// The lines Music has actually been seen starting, with when it started them. Lines it hasn't reached
    /// yet aren't in here — their times would be guesses, and guesses are what this exists to replace.
    @Published private(set) var anchors: [LineAnchor] = []
    @Published private(set) var status: Status = .off

    /// Apple's own line changes are the timing, so sample often enough to land within a beat of them.
    private static let interval: TimeInterval = 0.15

    private let position: () -> TimeInterval
    private var timer: Timer?
    private var scrollArea: AXUIElement?
    private var texts: [String] = []
    private var lastSearch: CFTimeInterval = 0

    init(position: @escaping () -> TimeInterval) {
        self.position = position
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
        sample()
    }

    /// A new track is playing. Whatever was read belongs to the old one, and if Music's pane isn't readable
    /// right now nothing will replace it, so drop it and let the fetched lyrics have their turn.
    func trackChanged() {
        texts = []
        lyrics = nil
        anchors = []
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scrollArea = nil
        texts = []
        lyrics = nil
        anchors = []
        status = .off
    }

    /// Whether macOS's prompt has already been put up this launch.
    private static var asked = false

    /// Asks for the permission this needs, showing macOS's prompt the first time.
    ///
    /// - Parameter force: ask even if this launch has asked already. Pressing a button that says so is a
    ///   request in itself, and the once-a-launch limit is there for the times nobody asked.
    static func requestPermission(force: Bool = false) {
        guard !AXIsProcessTrusted() else { return }
        if force { asked = false }
        // macOS puts its prompt up again on every call while the permission is missing, so switching this on
        // and off a few times means the same dialog a few times. Ask once a launch; after that the Sync tab
        // says what is missing and offers the button that opens the right pane.
        guard !asked else { return }
        asked = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func sample() {
        guard AXIsProcessTrusted() else {
            status = .needsPermission
            return
        }
        guard let area = lyricsArea() else {
            status = .needsLyricsPane
            return
        }
        let lines = MusicAccessibility.lyricLines(in: area)
        guard !lines.isEmpty else {
            status = .needsLyricsPane
            return
        }
        texts = lines.map(\.text)
        status = .reading(lines: texts.count)

        // Music's pane is virtualised: lines are built and thrown away as it scrolls, so the list changes
        // shape under us and an index from one sample means nothing in the next. Keying anything on the list
        // itself — as this did, resetting whenever it differed — threw away every line's timing each time
        // Music scrolled, which on a playing song is every few seconds. What is stable is the text of the
        // line Music has marked, and text is what these times are matched by anyway.
        guard let current = lines.first(where: \.selected)?.text, !current.isEmpty else { return }
        guard current != anchors.last?.text else { return }
        // It became current somewhere in the last sample, so split the difference.
        anchors.append(LineAnchor(text: current, start: max(0, position() - Self.interval / 2)))
        rebuild()
    }

    /// Builds lyrics from the lines on screen, timed by the ones Music has been seen reaching. Lines it
    /// hasn't reached yet get placeholder times that keep them in order; each is corrected the moment Music
    /// actually moves onto it.
    private func rebuild() {
        // Anchors are in the order Music sang them, so walking both in order pairs a repeated line with the
        // time it was sung rather than the first time it appears.
        var known: [TimeInterval?] = Array(repeating: nil, count: texts.count)
        var next = 0
        for anchor in anchors {
            guard let index = (next..<texts.count).first(where: { texts[$0] == anchor.text }) else { continue }
            known[index] = anchor.start
            next = index + 1
        }
        guard let lastKnown = known.lastIndex(where: { $0 != nil }), let start = known[lastKnown] else { return }

        let estimated = WordTiming.estimatedDuration(for: texts[lastKnown])
        var timeline: [TimeInterval] = []
        for i in texts.indices {
            if let time = known[i] {
                timeline.append(time)
            } else if i < lastKnown {
                // Never seen (the song was joined midway, or the pane scrolled past it before we looked);
                // park it just before the line that is known.
                timeline.append(max(0, start - Double(lastKnown - i) * 0.01))
            } else {
                timeline.append(start + estimated + Double(i - lastKnown - 1) * max(estimated, 1))
            }
        }
        let lines = texts.indices.map { i -> LyricLine in
            let end = i + 1 < timeline.count ? timeline[i + 1] : timeline[i] + estimated
            return LyricLine(
                start: timeline[i], end: end,
                words: WordTiming.estimate(text: texts[i], start: timeline[i], end: end))
        }
        lyrics = Lyrics(lines: lines, timing: .line, source: Self.sourceName)
    }

    private func lyricsArea() -> AXUIElement? {
        if let scrollArea, !MusicAccessibility.lyricLines(in: scrollArea).isEmpty { return scrollArea }
        // Finding it means walking Music's whole accessibility tree, which is thousands of elements. While the
        // pane is closed that would otherwise run at the sampling rate, so look again only now and then.
        let now = CACurrentMediaTime()
        guard now - lastSearch > 2 else { return nil }
        lastSearch = now
        guard let music = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Music").first
        else { return nil }
        scrollArea = MusicAccessibility.lyricsScrollArea(in: AXUIElementCreateApplication(music.processIdentifier))
        return scrollArea
    }
}
