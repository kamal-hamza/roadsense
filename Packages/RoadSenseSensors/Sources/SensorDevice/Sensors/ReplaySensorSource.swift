import Foundation
import SensorCore
import SensorRecording

/// Replays recorded readings (e.g. a sensor log from a real drive) as if they were live.
public struct ReplaySensorSource: SensorSource {
    public let recordedReadings: [SensorReading]
    /// Playback rate: `1` is real time, `0` is as fast as possible.
    public let speed: Double

    public init(readings: [SensorReading], speed: Double = 1) {
        recordedReadings = readings
        self.speed = speed
    }

    /// Loads a JSON Lines sensor log written by `FileSensorLogStore`.
    public init(logAt url: URL, speed: Double = 1) throws {
        try self.init(readings: FileSensorLogStore.readLog(at: url), speed: speed)
    }

    public func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        TimedReadingPlayer.play(recordedReadings, speed: speed)
    }
}
