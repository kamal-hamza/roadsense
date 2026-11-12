// swift-tools-version: 6.2

// =============================================================================
// RoadSenseKit - Layered architecture modules
// =============================================================================
// One Swift module per layer. Dependencies point inward only:
//
//   Presentation ──► Application ──► Domain
//   Infrastructure ──► Application ──► Domain
//
// The app target (RoadSense/) is the composition root: the only place that sees
// both Presentation and Infrastructure. See CODING_GUIDELINES.md §1.
// =============================================================================

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

let package = Package(
    name: "RoadSenseKit",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "Application", targets: ["Application"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .library(name: "Presentation", targets: ["Presentation"]),
    ],
    targets: [
        // Layers
        .target(name: "Domain", swiftSettings: coreSettings),
        .target(name: "Application", dependencies: ["Domain"], swiftSettings: coreSettings),
        .target(name: "Infrastructure", dependencies: ["Application", "Domain"], swiftSettings: coreSettings),
        .target(name: "Presentation", dependencies: ["Application", "Domain"], swiftSettings: uiSettings),

        // Tests (one per layer)
        .testTarget(name: "DomainTests", dependencies: ["Domain"], swiftSettings: coreSettings),
        .testTarget(
            name: "ApplicationTests",
            dependencies: ["Application", "Domain"],
            swiftSettings: coreSettings,
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: ["Infrastructure", "Application", "Domain"],
            swiftSettings: coreSettings,
        ),
        .testTarget(
            name: "PresentationTests",
            dependencies: ["Presentation", "Application", "Domain"],
            swiftSettings: uiSettings,
        ),
    ],
)
