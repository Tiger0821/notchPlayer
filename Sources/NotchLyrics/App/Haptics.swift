import AppKit

/// The taps the trackpad gives back while you change a setting.
///
/// macOS is sparing with these and so is this: they belong where a control lands on something — a slider
/// stepping, a row dropping into a new place, a choice moving to another one — and not on buttons, which
/// already feel like a press, or on anything that merely opens.
///
/// Nothing happens on a Mac without a Force Touch trackpad, or when the pointer is a mouse, so a control must
/// never depend on the tap to be understood.
enum Haptics {
    /// Something landed where it was going: a slider's step, a row's new place in a list.
    static func aligned() { perform(.alignment) }

    /// A choice moved to a different one, or a switch flipped.
    static func changed() { perform(.levelChange) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .drawCompleted)
    }
}
