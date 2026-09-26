// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mittari",
    platforms: [.macOS(.v26)],
    targets: [
        .target(
            name: "MittariCore",
            path: "Sources/MittariCore"
        ),
        .executableTarget(
            name: "Mittari",
            dependencies: ["MittariCore"],
            path: "Sources/Mittari"
        ),
        .testTarget(
            name: "MittariCoreTests",
            dependencies: ["MittariCore"],
            path: "Tests/MittariCoreTests"
        ),
    ]
)
