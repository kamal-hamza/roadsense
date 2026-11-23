import Foundation

/// Where a point falls relative to a route.
public struct RouteProjection: Hashable, Sendable {
    public let segmentIndex: Int
    /// Meters from the route's start to the closest point on the route.
    public let distanceAlongRoute: Double
    /// Meters from the point to the route.
    public let distanceFromRoute: Double
    /// Direction of travel on the route at that spot.
    public let routeBearing: Bearing
}
