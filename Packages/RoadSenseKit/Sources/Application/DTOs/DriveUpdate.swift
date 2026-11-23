import Domain

/// What the drive screen shows, refreshed as sensor data arrives.
public struct DriveUpdate: Hashable, Sendable {
    /// Speed in m/s.
    public var speed: Double?
    public var gpsStatus: GPSStatus
    /// Meters driven along the current route.
    public var distanceAlongRoute: Double
    public var routeLength: Double
    /// The next hotspot not yet warned about or passed.
    public var nextHotspot: RouteHotspot?
    /// The latest warning, kept until its hotspots are passed, for the on-screen banner.
    public var activeWarning: DriveWarning?
    /// Meters to the nearest hotspot in `activeWarning`.
    public var distanceToWarning: Double?
    public var isMuted: Bool
    /// False when driving without hazard data, or on a detour with no saved hotspots.
    public var hasHazardData: Bool
    public var hardBrakes: Int

    public init(
        speed: Double? = nil,
        gpsStatus: GPSStatus = .degraded,
        distanceAlongRoute: Double = 0,
        routeLength: Double = 0,
        nextHotspot: RouteHotspot? = nil,
        activeWarning: DriveWarning? = nil,
        distanceToWarning: Double? = nil,
        isMuted: Bool = false,
        hasHazardData: Bool = true,
        hardBrakes: Int = 0,
    ) {
        self.speed = speed
        self.gpsStatus = gpsStatus
        self.distanceAlongRoute = distanceAlongRoute
        self.routeLength = routeLength
        self.nextHotspot = nextHotspot
        self.activeWarning = activeWarning
        self.distanceToWarning = distanceToWarning
        self.isMuted = isMuted
        self.hasHazardData = hasHazardData
        self.hardBrakes = hardBrakes
    }
}
