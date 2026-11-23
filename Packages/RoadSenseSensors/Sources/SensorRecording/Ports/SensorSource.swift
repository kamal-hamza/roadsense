import SensorCore

/// How sensors should be configured while recording.
public struct SensorConfiguration: Hashable, Sendable {
    /// Device-motion sample rate. 50 Hz covers driving dynamics; bumps benefit from 100 Hz.
    public var motionRateHz: Double

    public init(motionRateHz: Double = 50) {
        self.motionRateHz = motionRateHz
    }
}

/// A source of sensor readings: live sensors, a replayed log, or a simulated drive.
public protocol SensorSource: Sendable {
    /// Starts the sensors and streams readings in order. Stop iterating to stop the sensors.
    func readings(configuration: SensorConfiguration) async -> AsyncStream<SensorReading>
}
