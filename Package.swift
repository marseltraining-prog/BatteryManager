// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediumWellBatteryCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MediumWellBatteryCore", targets: ["MediumWellBatteryCore"])],
    targets: [
        .target(name: "MediumWellBatteryCore"),
        .testTarget(name: "MediumWellBatteryCoreTests", dependencies: ["MediumWellBatteryCore"])
    ]
)
