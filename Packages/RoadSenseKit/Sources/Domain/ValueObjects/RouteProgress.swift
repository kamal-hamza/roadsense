import Foundation

/// Where the driver is along the planned route.
public struct RouteProgress: Hashable, Sendable {
    /// Meters driven along the route so far.
    public let distanceAlongRoute: Double
    /// Meters between the driver and the route.
    public let distanceFromRoute: Double
    /// Direction of the route where the driver is.
    public let routeBearing: Bearing
    /// The driver has been far from the route long enough to need a new one.
    public let isOffRoute: Bool

    public init(distanceAlongRoute: Double, distanceFromRoute: Double, routeBearing: Bearing, isOffRoute: Bool) {
        self.distanceAlongRoute = distanceAlongRoute
        self.distanceFromRoute = distanceFromRoute
        self.routeBearing = routeBearing
        self.isOffRoute = isOffRoute
    }
}
