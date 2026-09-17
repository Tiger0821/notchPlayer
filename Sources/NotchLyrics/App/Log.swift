import os

/// View with: log stream --predicate 'subsystem == "com.tigercho.NotchLyrics"' --level info
enum Log {
    static let music = Logger(subsystem: "com.tigercho.NotchLyrics", category: "music")
    static let lyrics = Logger(subsystem: "com.tigercho.NotchLyrics", category: "lyrics")
    static let notch = Logger(subsystem: "com.tigercho.NotchLyrics", category: "notch")
    static let sync = Logger(subsystem: "com.tigercho.NotchLyrics", category: "sync")
    static let pixelArt = Logger(subsystem: "com.tigercho.NotchLyrics", category: "pixel-art")
}
