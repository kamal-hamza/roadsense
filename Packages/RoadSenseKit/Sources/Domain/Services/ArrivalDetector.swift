import Foundation
import SensorCore

/// Notices when the driver has arrived: close to the destination and nearly stopped for a while.
public struct ArrivalDetector: Sendable {
    public struct Configuration: Hashable, Sendable {
        /// Meters from the destination that count as there.
        public var radius = 50.0
        /// Below this speed (m/s) counts as stopped. 5 km/h ≈ 1.39 m/s.
        public var maximumSpeed = 5.0 / 3.6
        /// Seconds the driver must stay close and slow.
        public var dwellTime: TimeInterval = 30

        public init() {}
    }

    public let configuration: Configuration
    public let destination: Coordinate
    private var settledSince: Date?

    public init(destination: Coordinate, configuration: Configuration = Configuration()) {
        self.destination = destination
        self.configuration = configuration
    }

    /// Updates with a new fix and returns whether the driver has arrived.
    public mutating func process(_ fix: LocationSample) -> Bool {
        let isClose = fix.coordinate.distance(to: destination) <= configuration.radius
        // GPS reports speed as invalid when stopped, so a missing speed counts as slow.
        let isSlow = (fix.speed ?? 0) < configuration.maximumSpeed
        guard isClose, isSlow else {
            settledSince = nil
            return false
        }
        let since = settledSince ?? fix.timestamp
        settledSince = since
        return fix.timestamp.timeIntervalSince(since) >= configuration.dwellTime
    }
}
