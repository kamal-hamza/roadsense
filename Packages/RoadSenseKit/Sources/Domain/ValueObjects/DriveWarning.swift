import Foundation

/// A warning about one or more hotspots ahead ("2 hazards ahead" when grouped).
public struct DriveWarning: Hashable, Sendable {
    /// The hotspots covered by this warning, nearest first.
    public let hotspots: [RouteHotspot]
    /// Meters to the nearest hotspot when the warning was given.
    public let distance: Double
    /// Speed in m/s when the warning was given.
    public let speed: Double?
    /// Warnings were muted, so nothing was shown or spoken; it's only logged.
    public let isSuppressed: Bool
    public let timestamp: Date

    public init(hotspots: [RouteHotspot], distance: Double, speed: Double?, isSuppressed: Bool, timestamp: Date) {
        self.hotspots = hotspots
        self.distance = distance
        self.speed = speed
        self.isSuppressed = isSuppressed
        self.timestamp = timestamp
    }
}
