import SensorCore

/// How sensors should be configured while recording.
public struct SensorConfiguration: Hashable, Sendable {
    /// Device-motion sample rate. 50 Hz covers driving dynamics; bumps benefit from 100 Hz.
    public var motionRateHz: Double
    /// The path the drive is expected to follow. Real sensors ignore it; simulated sources drive along it.
    public var plannedPath: [Coordinate]

    public init(motionRateHz: Double = 50, plannedPath: [Coordinate] = []) {
        self.motionRateHz = motionRateHz
        self.plannedPath = plannedPath
    }
}

/// A source of sensor readings: live sensors, a replayed log, or a simulated drive.
public protocol SensorSource: Sendable {
    /// Starts the sensors and streams readings in order. Stop iterating to stop the sensors.
    func readings(configuration: SensorConfiguration) async -> AsyncStream<SensorReading>
}
