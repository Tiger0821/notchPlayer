import Foundation

/// Drawing on a square canvas of 0xRRGGBBAA pixels, as the pixel editor does.
public enum PixelCanvas {
    public static let size = PixelSprite.maxSize

    public struct Point: Equatable, Sendable {
        public var x: Int
        public var y: Int

        public init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }
    }

    public static func blankFrame() -> [UInt32] {
        Array(repeating: 0, count: size * size)
    }

    /// The sprite's frames centered on full-size canvases.
    public static func frames(for sprite: PixelSprite) -> [[UInt32]] {
        let left = (size - sprite.width) / 2, top = (size - sprite.height) / 2
        return sprite.frames.map { frame in
            var canvas = blankFrame()
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    canvas[(y + top) * size + x + left] = frame[y * sprite.width + x]
                }
            }
            return canvas
        }
    }

    /// Every point on a straight line, both ends included, so fast strokes don't leave holes.
    public static func line(from start: Point, to end: Point) -> [Point] {
        var points: [Point] = []
        var x = start.x, y = start.y
        let dx = abs(end.x - x), dy = -abs(end.y - y)
        let stepX = x < end.x ? 1 : -1, stepY = y < end.y ? 1 : -1
        var error = dx + dy
        while true {
            points.append(Point(x: x, y: y))
            if x == end.x, y == end.y { break }
            let doubled = 2 * error
            if doubled >= dy {
                error += dy
                x += stepX
            }
            if doubled <= dx {
                error += dx
                y += stepY
            }
        }
        return points
    }

    /// Paints `color` over the area of same-colored pixels around `point`, not crossing diagonals.
    public static func fill(_ frame: inout [UInt32], at point: Point, with color: UInt32) {
        let target = frame[point.y * size + point.x]
        guard target != color else { return }
        var stack = [point]
        while let next = stack.popLast() {
            let index = next.y * size + next.x
            guard frame[index] == target else { continue }
            frame[index] = color
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = next.x + dx, y = next.y + dy
                if (0..<size).contains(x), (0..<size).contains(y) { stack.append(Point(x: x, y: y)) }
            }
        }
    }

    /// Mirrored left to right.
    public static func flipped(_ frame: [UInt32]) -> [UInt32] {
        (0..<size).flatMap { y in (0..<size).reversed().map { x in frame[y * size + x] } }
    }
}
