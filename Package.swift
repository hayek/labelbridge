// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LabelBridge",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "LabelCore", targets: ["LabelCore"]),
        .executable(name: "LabelBridgeApp", targets: ["LabelBridgeApp"]),
        .executable(name: "labelbridge", targets: ["labelbridge"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
    ],
    targets: [
        .target(name: "LabelCore"),
        .executableTarget(name: "LabelBridgeApp", dependencies: ["LabelCore"]),
        .executableTarget(name: "labelbridge", dependencies: [
            "LabelCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "LabelCoreTests", dependencies: ["LabelCore"]),
    ]
)
