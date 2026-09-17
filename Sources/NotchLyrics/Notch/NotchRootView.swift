import LyricsCore
import SwiftUI

struct NotchRootView: View {
    let geometry: NotchGeometry
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var music: MusicController
    @ObservedObject var sync: AutoSyncController
    @ObservedObject var settings: AppSettings
    @ObservedObject var pixelArt: PixelArtLibrary

    var body: some View {
        let wing = geometry.clampedWing(settings.wingWidth)

        LyricsBar(model: model, music: music, sync: sync, settings: settings, pixelArt: pixelArt,
                  wing: wing, notchWidth: geometry.notchWidth, hasRealNotch: geometry.hasRealNotch)
            .frame(width: geometry.width(wing: wing), height: geometry.barHeight)
            .background(
                UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10, style: .continuous)
                    .fill(Color.black)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea()
            .environment(\.colorScheme, .dark)
    }
}

/// What each strip beside the notch shows. Every line keeps the side its number gives it, so a line already
/// waiting dimmed on one side simply lights up when it starts — only the other side gets new text.
struct BarContent {
    enum Slot: Equatable {
        case line(LyricLine, index: Int)
        case text(String, dimmed: Bool)
        case gap
        case empty

        /// Identity for the strip: while this stays the same, the strip changes in place instead of animating.
        var identity: String {
            switch self {
            case .line(_, let index): "line-\(index)"
            case .text(let text, _): "text-\(text)"
            case .gap: "gap"
            case .empty: "empty"
            }
        }
    }

    var left: Slot
    var right: Slot

    private init(current: Slot, onLeft: Bool, other: Slot) {
        left = onLeft ? current : other
        right = onLeft ? other : current
    }

    static func make(state: NowPlayingModel.LyricsState, track: TrackInfo?, time: TimeInterval) -> BarContent {
        guard let track else { return BarContent(current: .empty, onLeft: true, other: .empty) }

        switch state {
        case .loaded(let lyrics):
            let nextIndex: (Int) -> Int? = { from in
                lyrics.lines[from...].indices.first { !lyrics.lines[$0].isBlank }
            }
            guard let index = lyrics.lineIndex(at: time) else {
                // Before the song's first line: park it on its own side so it doesn't jump when it starts.
                guard let first = nextIndex(0) else {
                    return BarContent(current: .text(track.title, dimmed: false), onLeft: true, other: .empty)
                }
                return BarContent(current: .line(lyrics.lines[first], index: first),
                                  onLeft: lyrics.lineOrdinals[first].isMultiple(of: 2),
                                  other: .text(track.title, dimmed: false))
            }

            let line = lyrics.lines[index]
            let upcoming = nextIndex(index + 1)
            let next: Slot = upcoming.map { .line(lyrics.lines[$0], index: $0) } ?? .empty
            // With real word timing we know when singing stops, so show a rest marker during long instrumentals.
            let gapAhead = upcoming.map { lyrics.lines[$0].start } ?? .infinity
            let longBreak = lyrics.timing == .word && time > line.end + 0.6 && gapAhead - time > 3
            let current: Slot = line.isBlank || longBreak ? .gap : .line(line, index: index)
            return BarContent(current: current, onLeft: lyrics.lineOrdinals[index].isMultiple(of: 2), other: next)

        case .loading:
            return BarContent(current: .text(track.title, dimmed: false), onLeft: true,
                              other: .text("Searching lyrics…", dimmed: true))
        case .notFound, .idle:
            return BarContent(current: .text(track.title, dimmed: false), onLeft: true,
                              other: .text(track.artist, dimmed: true))
        }
    }
}

/// The bar runs behind the notch, so that stretch of it is never seen — except for the moment a Space slides
/// past. Something belongs there.
struct NotchSecret: View {
    let width: CGFloat
    /// Displays without a real notch draw their own, and would show this off, so they get nothing.
    let hidden: Bool

    /// Name and version, from the bundle, so it can't drift out of date.
    private var label: String {
        let info = Bundle.main.infoDictionary
        let name = info?["CFBundleName"] as? String ?? "NotchLyrics"
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        return version.isEmpty ? name.uppercased() : "\(name.uppercased()) \(version)"
    }

    var body: some View {
        Text(hidden ? label : "")
            .font(.system(size: 7, weight: .medium, design: .rounded))
            .kerning(1.6)
            .foregroundStyle(Color.white.opacity(0.14))
            .lineLimit(1)
            .frame(width: width)
    }
}

struct LyricsBar: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var music: MusicController
    @ObservedObject var sync: AutoSyncController
    @ObservedObject var settings: AppSettings
    @ObservedObject var pixelArt: PixelArtLibrary
    let wing: CGFloat
    let notchWidth: CGFloat
    let hasRealNotch: Bool

    private var textWidth: CGFloat {
        max(wing - NotchLayout.wingInnerPadding - NotchLayout.wingOuterPadding, 0)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !music.isPlaying || !settings.enabled)) { _ in
            let time = music.position() + sync.correction
            let content = BarContent.make(state: model.lyricsState, track: music.track, time: time)

            HStack(spacing: 0) {
                strip(content.left, alignment: .trailing, time: time)
                    .padding(.leading, NotchLayout.wingOuterPadding)
                    .padding(.trailing, NotchLayout.wingInnerPadding)
                    .frame(width: wing)
                NotchSecret(width: notchWidth, hidden: hasRealNotch)
                strip(content.right, alignment: .leading, time: time)
                    .padding(.leading, NotchLayout.wingInnerPadding)
                    .padding(.trailing, NotchLayout.wingOuterPadding)
                    .frame(width: wing)
            }
            .clipped()
        }
    }

    /// One strip. Text hugs the notch: the left strip is right-aligned, the right strip left-aligned.
    @ViewBuilder
    private func strip(_ slot: BarContent.Slot, alignment: Alignment, time: TimeInterval) -> some View {
        let fontSize = CGFloat(settings.fontSize)

        Group {
            switch slot {
            case .line(let line, _):
                // A line that hasn't started has no sung words yet, so it reads as the dimmed line coming up.
                KaraokeLineView(line: line, time: time, fontSize: fontSize, width: textWidth, alignment: alignment,
                                art: settings.pixelArtEnabled ? pixelArt.art(for: line) : [:],
                                whiteArt: settings.pixelArtWhite,
                                artDirection: alignment == .trailing ? -1 : 1)
            case .text(let text, let dimmed):
                Text(text)
                    .font(.system(size: fontSize, weight: dimmed ? .medium : .semibold))
                    .foregroundStyle(Color.white.opacity(dimmed ? 0.45 : 0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: textWidth, alignment: alignment)
            case .gap:
                Image(systemName: "music.note")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: textWidth, alignment: alignment)
            case .empty:
                Color.clear.frame(width: textWidth)
            }
        }
        .id(slot.identity)
        // New text just brightens into place; nothing slides.
        .transition(.asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.45)),
                                removal: .opacity.animation(.easeIn(duration: 0.25))))
        .animation(.easeInOut(duration: 0.3), value: slot.identity)
    }
}
