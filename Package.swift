// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Storyteller",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Storyteller",
            path: "Sources/ScrivenerReader",
            linkerSettings: [
                // Required for MPRemoteCommandCenter / MPNowPlayingInfoCenter
                .linkedFramework("MediaPlayer")
            ]
        )
    ]
)
