// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MotionFXCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MotionFXCore", targets: ["MotionFXCore"]),
    ],
    targets: [
        .target(name: "MotionFXCore"),
        .testTarget(name: "MotionFXCoreTests", dependencies: ["MotionFXCore"]),
    ]
)
