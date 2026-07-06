// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RolandFP30XController",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "RolandFP30XController", targets: ["RolandFP30XController"]),
        .library(name: "RolandMIDI", targets: ["RolandMIDI"]),
    ],
    targets: [
        .target(
            name: "RolandMIDI",
            path: "Sources/RolandMIDI"
        ),
        .executableTarget(
            name: "RolandFP30XController",
            dependencies: ["RolandMIDI"],
            path: "Sources/RolandFP30XController",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "RolandMIDITests",
            dependencies: ["RolandMIDI"],
            path: "Tests/RolandMIDITests"
        ),
    ]
)
