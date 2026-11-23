import Foundation

/// The driver's position on the route at one moment, as the warning engine sees it.
public struct DrivePosition: Hashable, Sendable {
    public let timestamp: Date
    /// Meters driven along the route.
    public let distanceAlongRoute: Double
    /// Speed in m/s, or `nil` when the GPS reports it as invalid.
    public let speed: Double?
    /// Direction of travel from GPS, or `nil` when invalid (e.g. stopped).
    public let heading: Bearing?

    public init(timestamp: Date, distanceAlongRoute: Double, speed: Double?, heading: Bearing?) {
        self.timestamp = timestamp
        self.distanceAlongRoute = distanceAlongRoute
        self.speed = speed
        self.heading = heading
    }
}
