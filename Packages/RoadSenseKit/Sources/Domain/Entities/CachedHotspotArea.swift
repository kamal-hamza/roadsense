import Foundation
import SensorCore

/// Hotspots fetched for one route, kept on the phone so warnings still work offline.
public struct CachedHotspotArea: Hashable, Sendable, Codable {
    /// The route the hotspots were fetched for; it defines the area they cover.
    public let route: Route
    public let hotspots: [Hotspot]
    public let savedAt: Date

    public init(route: Route, hotspots: [Hotspot], savedAt: Date) {
        self.route = route
        self.hotspots = hotspots
        self.savedAt = savedAt
    }

    /// Whether this area's route runs along most of `other`, so its hotspots can stand in for a fresh lookup.
    /// - Parameters:
    ///   - tolerance: Meters a point of `other` may be from this route and still count as covered.
    ///   - requiredFraction: Share of `other`'s sample points that must be covered.
    /// - Complexity: O(*k* × *s*): up to 200 sample points of `other` times this route's segments.
    public func covers(_ other: Route, tolerance: Double = 100, requiredFraction: Double = 0.9) -> Bool {
        let samples = Self.samplePoints(of: other, maximumCount: 200)
        let covered = samples.count { route.projection(of: $0).distanceFromRoute <= tolerance }
        return Double(covered) >= requiredFraction * Double(samples.count)
    }

    /// Up to `maximumCount` of the route's points, evenly spread, always including both ends.
    private static func samplePoints(of route: Route, maximumCount: Int) -> [Coordinate] {
        let points = route.points
        guard points.count > maximumCount else { return points }
        let step = Double(points.count - 1) / Double(maximumCount - 1)
        return (0 ..< maximumCount).map { points[Int((Double($0) * step).rounded())] }
    }
}
