import SwiftUI

/// Drops down from the notch when the lyrics bar is clicked.
struct ControlsPanel: View {
    @ObservedObject var model: NowPlayingModel
    @ObservedObject var music: MusicController
    @ObservedObject var settings: AppSettings
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(music.track?.title ?? "Not playing")
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(music.track?.artist ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                    Text(model.sourceDescription)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 18) {
                    controlButton("backward.fill", size: 15) { music.previousTrack() }
                    controlButton(music.isPlaying ? "pause.fill" : "play.fill", size: 20) { music.playPause() }
                    controlButton("forward.fill", size: 15) { music.nextTrack() }
                }
            }

            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                progressRow(position: music.position(), duration: music.track?.duration ?? 0)
            }

            HStack(spacing: 6) {
                Text("Lyrics timing")
                    .foregroundStyle(.white.opacity(0.5))
                controlButton("minus.circle", size: 12) { settings.offsetMs -= 100 }
                    .help("Show lyrics later")
                Text(String(format: "%+.1fs", settings.offsetMs / 1000))
                    .monospacedDigit()
                    .frame(width: 38)
                controlButton("plus.circle", size: 12) { settings.offsetMs += 100 }
                    .help("Show lyrics earlier")
                Spacer()
                controlButton("arrow.clockwise", size: 12) { model.reload() }
                    .help("Reload lyrics")
                controlButton("gearshape", size: 12, action: openSettings)
                    .help("Settings")
            }
            .font(.system(size: 11))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var artwork: some View {
        Group {
            if let image = music.artwork {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note").foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func progressRow(position: TimeInterval, duration: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Text(format(position))
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.2))
                    Capsule().fill(.white.opacity(0.85))
                        .frame(width: duration > 0 ? proxy.size.width * min(max(position / duration, 0), 1) : 0)
                }
            }
            .frame(height: 4)
            Text(format(duration))
        }
        .font(.system(size: 10).monospacedDigit())
        .foregroundStyle(.white.opacity(0.5))
    }

    private func controlButton(_ symbol: String, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(minWidth: 20, minHeight: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
