// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceOverlay",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "VoiceOverlay", targets: ["VoiceOverlay"]),
        .library(name: "VoiceOverlayCore", targets: ["VoiceOverlayCore"]),
    ],
    targets: [
        .target(name: "VoiceOverlayCore"),
        .executableTarget(
            name: "VoiceOverlay",
            dependencies: ["VoiceOverlayCore"]
        ),
        .executableTarget(
            name: "VoiceOverlayTestRunner",
            dependencies: ["VoiceOverlayCore"],
            path: "Tests/VoiceOverlayTestRunner"
        ),
    ]
)
