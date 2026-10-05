// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MediumWellBatteryCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MediumWellBatteryCore", targets: ["MediumWellBatteryCore"]),
        .executable(name: "BatteryManager", targets: ["BatteryManagerApp"])
    ],
    targets: [
        .target(name: "CSMC", path: "Sources/CSMC"),
        .target(name: "MediumWellBatteryCore", dependencies: ["CSMC"]),
        .executableTarget(
            name: "BatteryManagerApp",
            dependencies: ["MediumWellBatteryCore"],
            path: "App"),
        .testTarget(
            name: "MediumWellBatteryCoreTests",
            dependencies: ["MediumWellBatteryCore"])
    ]
)
