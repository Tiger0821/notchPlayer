import Foundation
import os

/// Thread-safe copy of the playback anchor, so audio threads can turn a capture time into a song position.
final class PlaybackClock: Sendable {
    struct Anchor: Sendable {
        var trackID: String?
        var position: TimeInterval
        var time: CFTimeInterval
        var isPlaying: Bool
    }

    private let anchor = OSAllocatedUnfairLock(initialState: Anchor(trackID: nil, position: 0, time: 0, isPlaying: false))

    func update(_ newAnchor: Anchor) {
        anchor.withLock { $0 = newAnchor }
    }

    /// Song position at a CACurrentMediaTime-based host time.
    func position(at time: CFTimeInterval) -> (trackID: String?, position: TimeInterval, isPlaying: Bool) {
        anchor.withLock { anchor in
            (anchor.trackID, anchor.isPlaying ? anchor.position + (time - anchor.time) : anchor.position, anchor.isPlaying)
        }
    }
}
