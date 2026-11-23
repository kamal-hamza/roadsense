import DriveSimulation
import Foundation
import SensorCore
import SensorRecording

/// Plays a synthetic drive in real time. Used in the iOS Simulator, which has no motion sensors.
public struct SimulatedSensorSource: SensorSource {
    public let segments: [DriveSegment]
    public let orientation: PhoneOrientation
    public let repetitions: Int

    public init(
        segments: [DriveSegment] = DriveSegment.demo,
        orientation: PhoneOrientation = .cupholder,
        repetitions: Int = 5,
    ) {
        self.segments = segments
        self.orientation = orientation
        self.repetitions = repetitions
    }

    public func readings(configuration: SensorConfiguration) async -> AsyncStream<SensorReading> {
        let drive = SyntheticDrive(
            segments: Array(repeating: segments, count: repetitions).flatMap(\.self),
            orientation: orientation,
            startDate: Date(),
            motionRateHz: configuration.motionRateHz,
            seed: UInt64.random(in: 1 ... UInt64.max),
        )
        return TimedReadingPlayer.play(drive.readings(), speed: 1)
    }
}
