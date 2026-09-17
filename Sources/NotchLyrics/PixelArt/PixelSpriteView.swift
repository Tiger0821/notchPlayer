import AppKit
import LyricsCore
import SwiftUI

/// Draws one frame of a sprite with crisp, unsmoothed pixels.
struct PixelSpriteView: View {
    let sprite: PixelSprite
    var frame = 0
    var white = false
    var pixelSize: CGFloat = 1

    var body: some View {
        if let image = PixelImageCache.image(for: sprite, frame: frame, white: white) {
            Image(decorative: image, scale: 1)
                .interpolation(.none)
                .resizable()
                .frame(width: CGFloat(sprite.width) * pixelSize, height: CGFloat(sprite.height) * pixelSize)
        }
    }
}

@MainActor
enum PixelImageCache {
    private struct Key: Hashable {
        var id: String
        var frame: Int
        var white: Bool
    }

    private struct Entry {
        var width: Int
        var pixels: [UInt32]
        var image: CGImage
    }

    private static var entries: [Key: Entry] = [:]

    static func image(for sprite: PixelSprite, frame: Int, white: Bool) -> CGImage? {
        guard !sprite.frames.isEmpty else { return nil }
        let frame = min(max(frame, 0), sprite.frames.count - 1)
        let key = Key(id: sprite.id, frame: frame, white: white)
        let pixels = sprite.frames[frame]
        // Edited sprites keep their id, so the pixels themselves decide whether the cached image is still right.
        if let entry = entries[key], entry.width == sprite.width, entry.pixels == pixels { return entry.image }
        guard let image = makeImage(width: sprite.width, height: sprite.height, pixels: pixels, white: white) else { return nil }
        if entries.count > 1000 { entries.removeAll() }
        entries[key] = Entry(width: sprite.width, pixels: pixels, image: image)
        return image
    }

    private static func makeImage(width: Int, height: Int, pixels: [UInt32], white: Bool) -> CGImage? {
        guard width > 0, height > 0, pixels.count == width * height else { return nil }
        var bytes = [UInt8](repeating: 0, count: pixels.count * 4)
        for (index, color) in pixels.enumerated() where color & 0xFF != 0 {
            var alpha = Double(color & 0xFF) / 255
            var red = 1.0, green = 1.0, blue = 1.0
            if white {
                alpha *= PixelSprite.whiteLevel(for: color)
            } else {
                red = Double((color >> 24) & 0xFF) / 255
                green = Double((color >> 16) & 0xFF) / 255
                blue = Double((color >> 8) & 0xFF) / 255
            }
            // Premultiplied RGBA.
            bytes[index * 4] = UInt8((red * alpha * 255).rounded())
            bytes[index * 4 + 1] = UInt8((green * alpha * 255).rounded())
            bytes[index * 4 + 2] = UInt8((blue * alpha * 255).rounded())
            bytes[index * 4 + 3] = UInt8((alpha * 255).rounded())
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}

// MARK: - Motion

/// Where a sprite is drawn some time after its word starts, relative to its resting place beside the word.
struct SpritePose {
    var offset: CGSize = .zero
    var scale: CGFloat = 1
    var opacity: Double = 1
    var frame = 0
    /// How much of the sprite's gap in the line is open: 1 while it sits there, back to 0 after it has left.
    var gap: CGFloat = 1
}

enum SpriteMotion {
    static let pop: TimeInterval = 0.35
    private static let open: TimeInterval = 0.18
    /// Leaving sprites sit this long after popping in, so the picture registers before it moves.
    private static let linger: TimeInterval = 0.5

    /// Pixel size in points for lyrics at `fontSize`: whole or half points keep pixels even on Retina screens.
    static func pixelSize(fontSize: CGFloat) -> CGFloat {
        fontSize >= 17 ? 1.5 : 1
    }

    /// `direction` is +1 when leaving sprites should head right (away from the notch on the right side), −1 for left.
    static func pose(for sprite: PixelSprite, elapsed t: TimeInterval, direction: CGFloat) -> SpritePose {
        var pose = SpritePose()
        pose.frame = sprite.frameIndex(at: t)
        pose.gap = easeOut(t / open)

        // Pop: grow past full size, then settle.
        let popped = clamp(t / pop)
        pose.scale = popped < 0.6 ? easeOut(popped / 0.6) * 1.3 : 1.3 - 0.3 * easeInOut((popped - 0.6) / 0.4)
        let idle = t - pop

        switch sprite.motion {
        case .stay:
            break
        case .bounce:
            let hop = 0.42
            if idle > 0, idle < hop * 3 {
                pose.offset.height = -abs(sin(idle / hop * .pi)) * 3
            }
        case .beat:
            if idle > 0 {
                let beat = idle.truncatingRemainder(dividingBy: 0.9)
                pose.scale *= 1 + 0.16 * bump(beat, from: 0, length: 0.14) + 0.1 * bump(beat, from: 0.22, length: 0.14)
            }
        case .twinkle:
            if idle > 0 {
                let wave = cos(idle * 2 * .pi / 1.2)
                pose.opacity = 0.72 + 0.28 * wave
                pose.scale *= 1 + 0.07 * wave
            }
        case .drive, .fly, .float, .fall:
            let away = idle - linger
            guard away > 0 else { break }
            let done: TimeInterval
            switch sprite.motion {
            case .drive:
                pose.offset.width = direction * (30 * away + 150 * away * away)
                pose.offset.height = Int(away * 14) % 2 == 0 ? 0 : -0.5
                done = 2
            case .fly:
                pose.offset.width = direction * (22 * away + 90 * away * away)
                pose.offset.height = -(5 * away + 28 * away * away)
                done = 1.6
            case .float:
                pose.offset.width = sin(away * 5) * 2
                pose.offset.height = -(12 * away + 10 * away * away)
                pose.opacity = 1 - clamp(away / 1.3)
                done = 1.3
            default:
                pose.offset.height = 8 * away + 45 * away * away
                pose.opacity = 1 - clamp(away / 0.9)
                done = 0.9
            }
            if away >= done { pose.opacity = 0 }
            // Once it's on its way, the words beside it close the gap.
            pose.gap = 1 - easeInOut((away - 0.2) / 0.3)
        }
        return pose
    }

    /// Vehicles and fliers face the way they're going.
    static func isMirrored(_ sprite: PixelSprite, direction: CGFloat) -> Bool {
        direction < 0 && (sprite.motion == .drive || sprite.motion == .fly)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private static func easeOut(_ value: Double) -> Double {
        let x = clamp(value)
        return 1 - (1 - x) * (1 - x)
    }

    private static func easeInOut(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    /// A single smooth hump over `length` seconds starting at `from`.
    private static func bump(_ time: Double, from start: Double, length: Double) -> Double {
        let x = (time - start) / length
        return x > 0 && x < 1 ? sin(x * .pi) : 0
    }
}
