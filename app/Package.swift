// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VerbVox",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "VerbVox",
            dependencies: ["VerbVoxCore"],
            path: "Sources/VerbVox"
        ),
        .target(
            name: "VerbVoxCore",
            path: "Sources/VerbVoxCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "VerbVoxCoreTests",
            dependencies: ["VerbVoxCore"],
            path: "Tests/VerbVoxCoreTests"
        ),
    ]
)
