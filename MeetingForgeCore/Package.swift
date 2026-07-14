// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MeetingForgeCore",
    platforms: [.macOS("26.0")],
    products: [
        .library(name: "MeetingForgeCore", targets: ["MeetingForgeCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.7.0"),
        .package(url: "https://github.com/JohnSundell/Ink.git", from: "0.6.0"),
        // Transitive pin: swift-transformers 1.1.x (pulled in by WhisperKit) is not
        // source-compatible with swift-jinja 2.4.0's new ObjectKey type (introduced in
        // huggingface/swift-jinja#67). Pin to the last version before that break so the
        // build compiles; swift-transformers itself only requires `from: "2.0.0"`.
        .package(url: "https://github.com/huggingface/swift-jinja.git", exact: "2.3.6"),
    ],
    targets: [
        .target(
            name: "MeetingForgeCore",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Ink", package: "Ink"),
            ]
        ),
        .testTarget(name: "MeetingForgeCoreTests", dependencies: ["MeetingForgeCore"]),
    ]
)
