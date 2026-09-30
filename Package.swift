// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Mittari",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
        .package(url: "https://github.com/gabry-ts/partiti-ui", from: "0.2.0"),
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
                .product(name: "PartitiUI", package: "partiti-ui"),
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
