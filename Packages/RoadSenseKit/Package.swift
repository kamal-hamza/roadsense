// swift-tools-version: 6.2

// One module per layer; dependencies point inward. See CODING_GUIDELINES.md §1.

import PackageDescription

/// Settings for the non-UI layers: Swift 6 strict concurrency, nonisolated by default.
let coreSettings: [SwiftSetting] = [
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

/// Settings for the UI layer: main-actor isolated by default, like the app target.
let uiSettings: [SwiftSetting] = coreSettings + [
    .defaultIsolation(MainActor.self),
]

let sensorCore: Target.Dependency = .product(name: "SensorCore", package: "RoadSenseSensors")
let sensorRecording: Target.Dependency = .product(name: "SensorRecording", package: "RoadSenseSensors")
let driveSimulation: Target.Dependency = .product(name: "DriveSimulation", package: "RoadSenseSensors")

let package = Package(
    name: "RoadSenseKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "Presentation", targets: ["Presentation"]),
    ],
    dependencies: [
        .package(path: "../RoadSenseSensors"),
    ],
    targets: [
        // Layers
        .target(name: "Domain", dependencies: [sensorCore], swiftSettings: coreSettings),
        .target(
            name: "Application",
            dependencies: ["Domain", sensorCore, sensorRecording],
            swiftSettings: coreSettings,
        ),
        .target(name: "Infrastructure", dependencies: ["Application", "Domain"], swiftSettings: coreSettings),
        .target(
            name: "Presentation",
            dependencies: ["Application", "Domain", sensorCore, sensorRecording],
            swiftSettings: uiSettings,
        ),

        // Tests (one per layer)
        .testTarget(name: "DomainTests", dependencies: ["Domain", sensorCore], swiftSettings: coreSettings),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Application", "Domain", sensorCore, sensorRecording, driveSimulation],
            swiftSettings: coreSettings,
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: ["Infrastructure", "Application", "Domain", sensorCore],
            swiftSettings: coreSettings,
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: ["Presentation", "Application", "Domain", sensorCore, sensorRecording],
            swiftSettings: uiSettings,
        ),
    ],
)
