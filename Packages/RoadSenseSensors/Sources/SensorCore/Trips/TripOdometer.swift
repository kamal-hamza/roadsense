import Foundation

/// Adds up distance driven from GPS fixes, ignoring inaccurate fixes and stationary drift.
public struct TripOdometer: Sendable {
    public var maximumHorizontalAccuracy = 50.0
    public var minimumSpeed = 1.0
    /// Larger jumps between fixes are treated as GPS glitches.
    public var maximumJump = 500.0

    public private(set) var meters = 0.0
    private var lastLocation: LocationSample?

    public init() {}

    public mutating func add(_ location: LocationSample) {
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= maximumHorizontalAccuracy else {
            return
        }
        // Accurate fixes always become the new reference point, even if we skip adding distance.
        defer { lastLocation = location }
        guard let lastLocation else { return }
        // GPS wanders a few meters while parked; don't count that as driving.
        if let speed = location.speed, speed < minimumSpeed {
            return
        }
        let distance = lastLocation.coordinate.distance(to: location.coordinate)
        if distance <= maximumJump {
            meters += distance
        }
    }
}
