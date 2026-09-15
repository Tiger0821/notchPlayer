// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NotchLyrics",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure lyrics logic (parsing, timing, fetching). No AppKit, so it's unit-testable.
        .target(name: "LyricsCore", path: "Sources/LyricsCore"),
        .executableTarget(name: "NotchLyrics", dependencies: ["LyricsCore"], path: "Sources/NotchLyrics"),
        .testTarget(name: "LyricsCoreTests", dependencies: ["LyricsCore"], path: "Tests/LyricsCoreTests"),
    ]
)
