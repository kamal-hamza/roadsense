import Foundation

/// A hotspot placed on a specific route.
public struct RouteHotspot: Identifiable, Hashable, Sendable, Codable {
    public let hotspot: Hotspot
    /// Meters from the route's start to the hotspot.
    public let distanceAlongRoute: Double

    public var id: UUID {
        hotspot.id
    }

    public init(hotspot: Hotspot, distanceAlongRoute: Double) {
        self.hotspot = hotspot
        self.distanceAlongRoute = distanceAlongRoute
    }
}
