// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KeyBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "KeyBar", targets: ["KeyBar"])],
    targets: [
        .target(name: "KeyBarCore"),
        .executableTarget(name: "KeyBar", dependencies: ["KeyBarCore"]),
        .testTarget(name: "KeyBarCoreTests", dependencies: ["KeyBarCore"])
    ]
)
