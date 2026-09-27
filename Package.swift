// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mittari",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "MittariCore",
            path: "Sources/MittariCore"
        ),
        .executableTarget(
            name: "Mittari",
            dependencies: [
                "MittariCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Mittari"
        ),
        .testTarget(
            name: "MittariCoreTests",
            dependencies: ["MittariCore"],
            path: "Tests/MittariCoreTests"
        ),
    ]
)
