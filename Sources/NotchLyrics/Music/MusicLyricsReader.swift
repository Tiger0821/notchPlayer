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
    static let sourceName = "Apple Music"

    enum Status: Equatable {
        case off
        case needsPermission
        /// Music is running but its lyrics pane isn't on screen to read.
        case needsLyricsPane
        case reading(lines: Int)
    }

    @Published private(set) var lyrics: Lyrics?
    @Published private(set) var status: Status = .off

    /// Apple's own line changes are the timing, so sample often enough to land within a beat of them.
    private static let interval: TimeInterval = 0.15

    private let position: () -> TimeInterval
    private var timer: Timer?
    private var scrollArea: AXUIElement?
    private var texts: [String] = []
    private var starts: [TimeInterval?] = []
    private var currentIndex: Int?
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
        starts = []
        currentIndex = nil
        lyrics = nil
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        scrollArea = nil
        texts = []
        starts = []
        currentIndex = nil
        lyrics = nil
        status = .off
    }

    /// Asks for the permission this needs, showing macOS's prompt the first time.
    static func requestPermission() {
        guard !AXIsProcessTrusted() else { return }
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

        let incoming = lines.map(\.text)
        if incoming != texts {
            // A different song, or the pane reloaded: start its timing over.
            texts = incoming
            starts = Array(repeating: nil, count: incoming.count)
            currentIndex = nil
        }
        status = .reading(lines: texts.count)

        // Music marks a run of lines; the first is the one being sung.
        guard let index = lines.firstIndex(where: \.selected) else { return }
        if index != currentIndex {
            currentIndex = index
            // It became current somewhere in the last sample, so split the difference.
            starts[index] = max(0, position() - Self.interval / 2)
            rebuild(around: index)
        }
    }

    /// Builds lyrics from the lines Apple has shown so far. Lines it hasn't reached yet get placeholder times
    /// that keep them in order; each is corrected the moment Music actually moves onto it.
    private func rebuild(around index: Int) {
        guard let start = starts[index] else { return }
        let estimated = WordTiming.estimatedDuration(for: texts[index])
        var timeline: [TimeInterval] = []
        for i in texts.indices {
            if let known = starts[i] {
                timeline.append(known)
            } else if i < index {
                // Never seen (the song was joined midway); park it just before the current line.
                timeline.append(max(0, start - Double(index - i) * 0.01))
            } else {
                timeline.append(start + estimated + Double(i - index - 1) * max(estimated, 1))
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
