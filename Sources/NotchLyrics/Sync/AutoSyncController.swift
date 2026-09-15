import AppKit
import Combine
import Foundation
import LyricsCore

/// Keeps lyrics in time with what you hear, with no manual offset:
/// 1. Subtracts the output device's delay (e.g. AirPods over Bluetooth).
/// 2. Listens to Music, recognizes sung words on-device, and measures each song's real lyric offset.
/// 3. Remembers measured offsets per song, and learns a default for songs it hasn't measured yet.
@MainActor
final class AutoSyncController: ObservableObject {
    enum Status: Equatable {
        case off
        case waiting
        case preparingModel
        case listening
        case synced(offset: TimeInterval, matches: Int)
        case remembered(offset: TimeInterval)
        case noMatch
        case needsPermission
        case unavailable(String)
    }

    @Published private(set) var status: Status = .waiting
    /// Added to Music's reported position to get the lyric time being heard right now.
    @Published private(set) var correction: TimeInterval = 0

    let latency = OutputLatencyMonitor()

    private let music: MusicController
    private let model: NowPlayingModel
    private let settings: AppSettings
    private let defaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()

    private var lyricsKey: String?
    private var aligner: LyricsAligner?
    private var songOffset: TimeInterval?
    private var recentEstimates: [TimeInterval] = []
    private var finishedKeys = Set<String>()
    private var session: SyncSession?
    private var sessionKey: String?

    private static let offsetsKey = "syncOffsets"
    private static let biasHistoryKey = "syncBiasHistory"
    /// Listening stops after this much sung audio without a confident match.
    private static let listenLimit: TimeInterval = 150

    init(music: MusicController, model: NowPlayingModel, settings: AppSettings) {
        self.music = music
        self.model = model
        self.settings = settings
    }

    func start() {
        latency.start()

        Publishers.CombineLatest4(music.$track, music.$isPlaying, model.$lyricsState, settings.$autoSync)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.evaluate() }
            .store(in: &cancellables)

        latency.$latency
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCorrection() }
            .store(in: &cancellables)

        // The capture device is tied to the output device, so restart listening when it changes.
        latency.$deviceID
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.stopSession()
                self?.evaluate()
            }
            .store(in: &cancellables)
    }

    var statusDescription: String {
        switch status {
        case .off: "Auto-sync is off"
        case .waiting: "Auto-sync: waiting for lyrics"
        case .preparingModel: "Auto-sync: downloading speech model…"
        case .listening: "Auto-sync: listening…"
        case .synced(let offset, let matches): String(format: "Auto-synced (%+.2fs, %d matches)", offset, matches)
        case .remembered(let offset): String(format: "Auto-synced (%+.2fs, remembered)", offset)
        case .noMatch: "Auto-sync: couldn't match this song"
        case .needsPermission: "Auto-sync needs audio recording permission"
        case .unavailable(let reason): "Auto-sync unavailable: \(reason)"
        }
    }

    func openAudioPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Forgets remembered offsets and listens again.
    func resync() {
        if let lyricsKey {
            var offsets = rememberedOffsets
            offsets[lyricsKey] = nil
            defaults.set(offsets, forKey: Self.offsetsKey)
        }
        stopSession()
        lyricsKey = nil
        finishedKeys.removeAll()
        evaluate()
    }

    // MARK: - State machine

    private func evaluate() {
        guard let track = music.track, case .loaded(let lyrics) = model.lyricsState else {
            stopSession()
            lyricsKey = nil
            aligner = nil
            songOffset = nil
            status = settings.autoSync ? .waiting : .off
            updateCorrection()
            return
        }

        let key = "\(track.id)|\(lyrics.source)|\(lyrics.lines.count)"
        if key != lyricsKey {
            stopSession()
            lyricsKey = key
            aligner = LyricsAligner(lyrics: lyrics)
            recentEstimates = []
            songOffset = settings.autoSync ? rememberedOffsets[key] : nil
            status = songOffset.map { .remembered(offset: $0) } ?? (settings.autoSync ? .waiting : .off)
            updateCorrection()
        }

        guard settings.autoSync else {
            stopSession()
            songOffset = nil
            status = .off
            updateCorrection()
            return
        }

        let needsListening = !finishedKeys.contains(key) && rememberedOffsets[key] == nil
        if music.isPlaying && needsListening {
            startSession(lyrics: lyrics, trackID: track.id, key: key)
        } else if !music.isPlaying || !needsListening {
            stopSession()
        }
    }

    private func startSession(lyrics: Lyrics, trackID: String, key: String) {
        guard session == nil else { return }
        let session = SyncSession(trackID: trackID, clock: music.clock)
        self.session = session
        sessionKey = key
        if case .synced = status {} else { status = .listening }

        let phrases = Array(Set(lyrics.lines.map(\.text).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).prefix(120))
        let locale = Self.speechLocale(for: lyrics)
        Task {
            await session.start(locale: locale, phrases: phrases) { [weak self] event in
                Task { @MainActor in self?.handle(event, key: key) }
            }
        }
    }

    private func stopSession() {
        guard let session else { return }
        self.session = nil
        sessionKey = nil
        Task { await session.stop() }
    }

    private func handle(_ event: SyncSession.Event, key: String) {
        guard key == lyricsKey, key == sessionKey else { return }
        switch event {
        case .preparingModel:
            status = .preparingModel
        case .listening(let locale):
            Log.sync.info("session started (\(locale, privacy: .public))")
            if songOffset == nil { status = .listening }
        case .units(let units):
            aligner?.add(units)
            Log.sync.info("recognized \(units.count) units, matched phrases=\(self.aligner?.matchedPhraseCount ?? 0)")
            if let estimate = aligner?.estimate() { apply(estimate, key: key) }
        case .audio(let seconds, let silentFraction):
            if silentFraction > 0.98, seconds >= 10, songOffset == nil {
                // Music is playing but the tap hears nothing: the audio recording permission was denied.
                status = .needsPermission
                finish(key)
            } else if seconds >= Self.listenLimit {
                if songOffset == nil { status = .noMatch }
                finish(key)
            }
        case .failed(let message):
            Log.sync.error("sync failed: \(message, privacy: .public)")
            status = .unavailable(message)
            finish(key)
        }
    }

    private func apply(_ estimate: AlignmentEstimate, key: String) {
        let changed = songOffset.map { abs($0 - estimate.offset) > 0.05 } ?? true
        songOffset = estimate.offset
        status = .synced(offset: estimate.offset, matches: estimate.support)
        if changed {
            Log.sync.info("offset \(estimate.offset, format: .fixed(precision: 3))s support=\(estimate.support) agreement=\(estimate.agreement, format: .fixed(precision: 2))")
            updateCorrection()
        }

        recentEstimates.append(estimate.offset)
        let lastThree = recentEstimates.suffix(3)
        let stable = lastThree.count == 3 && (lastThree.max()! - lastThree.min()!) < 0.12
        if estimate.support >= 12 && stable {
            // Confident: remember it, teach the default, and stop listening to save power.
            var offsets = rememberedOffsets
            if offsets.count > 500 { offsets.removeAll() }
            offsets[key] = estimate.offset
            defaults.set(offsets, forKey: Self.offsetsKey)
            let history = (biasHistory + [estimate.offset]).suffix(15)
            defaults.set(Array(history), forKey: Self.biasHistoryKey)
            finish(key)
        }
    }

    private func finish(_ key: String) {
        finishedKeys.insert(key)
        stopSession()
    }

    private func updateCorrection() {
        let value = (songOffset ?? learnedBias) - latency.latency
        if abs(value - correction) > 0.001 { correction = value }
    }

    // MARK: - Persistence

    private var rememberedOffsets: [String: Double] {
        defaults.dictionary(forKey: Self.offsetsKey) as? [String: Double] ?? [:]
    }

    private var biasHistory: [Double] {
        defaults.array(forKey: Self.biasHistoryKey) as? [Double] ?? []
    }

    /// Median offset of recently measured songs: what an unmeasured song most likely needs.
    private var learnedBias: TimeInterval {
        let sorted = biasHistory.sorted()
        guard !sorted.isEmpty else { return 0 }
        return sorted[sorted.count / 2]
    }

    static func speechLocale(for lyrics: Lyrics) -> Locale {
        var han = 0, kana = 0, hangul = 0, latin = 0
        for line in lyrics.lines {
            for scalar in line.text.unicodeScalars {
                switch scalar.value {
                case 0x3040...0x30FF: kana += 1
                case 0x3400...0x4DBF, 0x4E00...0x9FFF: han += 1
                case 0xAC00...0xD7AF: hangul += 1
                case 0x41...0x5A, 0x61...0x7A: latin += 1
                default: break
                }
            }
        }
        if kana > 10 { return Locale(identifier: "ja-JP") }
        if hangul > han, hangul * 3 > latin { return Locale(identifier: "ko-KR") }
        if han * 3 > latin { return Locale(identifier: "zh-TW") }
        return Locale(identifier: "en-US")
    }
}
