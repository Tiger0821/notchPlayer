import LyricsCore
import SwiftUI

struct NotchRootView: View {
    @ObservedObject var ui: NotchUIState
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var music: MusicController
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    var body: some View {
        let geometry = ui.geometry
        let wing = geometry.clampedWing(settings.wingWidth)
        let collapsedWidth = geometry.width(wing: wing, expanded: false)
        let shape = UnevenRoundedRectangle(
            bottomLeadingRadius: ui.expanded ? 20 : 10,
            bottomTrailingRadius: ui.expanded ? 20 : 10,
            style: .continuous)

        VStack(spacing: 0) {
            LyricsBar(model: model, music: music, settings: settings, wing: wing, notchWidth: geometry.notchWidth)
                .frame(width: collapsedWidth, height: geometry.barHeight)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) { ui.expanded.toggle() }
                }

            if ui.expanded {
                ControlsPanel(model: model, music: music, settings: settings, openSettings: openSettings)
                    .frame(height: NotchLayout.controlsHeight)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(width: geometry.width(wing: wing, expanded: ui.expanded), alignment: .top)
        .background(shape.fill(Color.black))
        .clipShape(shape)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
    }
}

/// What the two strips beside the notch show at a given moment.
struct BarContent {
    enum Left {
        case karaoke(LyricLine)
        case plain(String)
        case gap
    }

    var left: Left
    var right: String
    /// Changes whenever the displayed line changes; drives the line transition.
    var lineID: Int

    static func make(state: NowPlayingModel.LyricsState, track: TrackInfo?, time: TimeInterval) -> BarContent {
        guard let track else { return BarContent(left: .plain(""), right: "", lineID: -1) }

        switch state {
        case .loaded(let lyrics):
            guard let index = lyrics.lineIndex(at: time) else {
                let first = lyrics.lines.first { !$0.isBlank }
                return BarContent(left: .plain(track.title), right: first?.text ?? track.artist, lineID: -2)
            }
            let line = lyrics.lines[index]
            let next = lyrics.lines[(index + 1)...].first { !$0.isBlank }
            // With real word timing we know when singing stops, so show a rest marker during long instrumentals.
            let longBreak = lyrics.timing == .word && time > line.end + 0.6 && (next?.start ?? .infinity) - time > 3
            if line.isBlank || longBreak {
                return BarContent(left: .gap, right: next?.text ?? "", lineID: index * 2 + 1)
            }
            return BarContent(left: .karaoke(line), right: next?.text ?? "", lineID: index * 2)
        case .loading:
            return BarContent(left: .plain(track.title), right: "Searching lyrics…", lineID: -3)
        case .notFound, .idle:
            return BarContent(left: .plain(track.title), right: track.artist, lineID: -4)
        }
    }
}

struct LyricsBar: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var music: MusicController
    @ObservedObject var settings: AppSettings
    let wing: CGFloat
    let notchWidth: CGFloat

    private var textWidth: CGFloat {
        max(wing - NotchLayout.wingInnerPadding - NotchLayout.wingOuterPadding, 0)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !music.isPlaying || !settings.enabled)) { _ in
            let time = music.position() + settings.offsetMs / 1000
            let content = BarContent.make(state: model.lyricsState, track: music.track, time: time)

            HStack(spacing: 0) {
                leftWing(content, time: time)
                    .padding(.leading, NotchLayout.wingOuterPadding)
                    .padding(.trailing, NotchLayout.wingInnerPadding)
                    .frame(width: wing)
                Color.clear.frame(width: notchWidth)
                rightWing(content)
                    .padding(.leading, NotchLayout.wingInnerPadding)
                    .padding(.trailing, NotchLayout.wingOuterPadding)
                    .frame(width: wing)
            }
            .clipped()
            .animation(.easeInOut(duration: 0.28), value: content.lineID)
        }
    }

    private func leftWing(_ content: BarContent, time: TimeInterval) -> some View {
        let fontSize = CGFloat(settings.fontSize)
        return Group {
            switch content.left {
            case .karaoke(let line):
                KaraokeLineView(line: line, time: time, fontSize: fontSize, width: textWidth)
            case .plain(let text):
                Text(text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: textWidth, alignment: .trailing)
            case .gap:
                Image(systemName: "music.note")
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.5))
                    .frame(width: textWidth, alignment: .trailing)
            }
        }
        .id(content.lineID)
        .transition(.push(from: .bottom))
    }

    private func rightWing(_ content: BarContent) -> some View {
        Text(content.right)
            .font(.system(size: CGFloat(settings.fontSize) * 0.92, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: textWidth, alignment: .leading)
            .id(content.lineID)
            .transition(.push(from: .bottom))
    }
}
