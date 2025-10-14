// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ot2aat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ot2aat",
            targets: ["ot2aat"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "ot2aat",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "ot2aatTests",
            dependencies: ["ot2aat"]
        )
    ]
)
