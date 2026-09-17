import AppKit

// A second copy would draw a second strip over the notch, put a second icon in the menu bar, and poll Music
// twice, all of it invisible except as duplicated lyrics. Hand over to the copy already running instead.
let mine = ProcessInfo.processInfo.processIdentifier
let running = NSRunningApplication
    .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .first { $0.processIdentifier != mine }
if let running {
    // Launching it again is how you ask for its window, so open the one it already has.
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name("com.tigercho.NotchLyrics.showSettings"), object: nil, deliverImmediately: true)
    running.activate()
    exit(0)
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(delegate) {
        app.run()
    }
}
