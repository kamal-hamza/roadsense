import Foundation

/// When to warn about a hotspot ahead. See docs/MVP_USE_CASE_1.md §1 for the numbers.
public struct WarningPolicy: Hashable, Sendable {
    /// Always warn at least this many meters ahead, even when slow.
    public var minimumDistance = 150.0
    /// Seconds of warning to give at higher speeds.
    public var leadTime: TimeInterval = 7
    /// Degrees the driver's heading may differ from the hotspot's direction.
    public var headingTolerance = 45.0

    public init() {}

    /// How far ahead to warn, in meters, at `speed` m/s.
    public func warningDistance(speed: Double?) -> Double {
        // Faster means warn earlier, so the driver always gets ~7 s; stopped in traffic still gets 150 m.
        max(minimumDistance, max(0, speed ?? 0) * leadTime)
    }

    /// Whether the driver is heading the hotspot's way. With no heading (GPS course invalid), trust the route.
    public func isHeading(_ heading: Bearing?, alignedWith hotspot: Hotspot) -> Bool {
        guard let heading else { return true }
        return heading.isAligned(with: hotspot.bearing, tolerance: headingTolerance)
    }
}
