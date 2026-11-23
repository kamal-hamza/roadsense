// swift-tools-version: 6.2
import PackageDescription

let settings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "RoadSenseSensors",
    // added macos for lsp
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SensorCore", targets: ["SensorCore"]),
        .library(name: "SensorRecording", targets: ["SensorRecording"]),
        .library(name: "SensorDevice", targets: ["SensorDevice"]),
        .library(name: "DriveSimulation", targets: ["DriveSimulation"]),
    ],
    targets: [
        .target(name: "SensorCore", swiftSettings: settings),
        .target(name: "SensorRecording", dependencies: ["SensorCore"], swiftSettings: settings),
        .target(
            name: "SensorDevice",
            dependencies: ["SensorRecording", "SensorCore", "DriveSimulation"],
            swiftSettings: settings,
        ),
        .target(name: "DriveSimulation", dependencies: ["SensorCore"], swiftSettings: settings),

        .testTarget(
            name: "SensorCoreTests",
            dependencies: ["SensorCore", "DriveSimulation"],
            swiftSettings: settings,
        ),
        .testTarget(
            name: "SensorRecordingTests",
            dependencies: ["SensorRecording", "SensorCore", "DriveSimulation"],
            swiftSettings: settings,
        ),
        .testTarget(
            name: "SensorDeviceTests",
            dependencies: ["SensorDevice", "SensorRecording", "SensorCore", "DriveSimulation"],
            swiftSettings: settings,
        ),
    ],
)
