import Foundation
import SensorCore

/// Emits pre-recorded readings with their original spacing (scaled by `speed`).
enum TimedReadingPlayer {
    /// - Parameter speed: Playback rate. `1` is real time; `0` emits everything immediately.
    static func play(_ readings: [SensorReading], speed: Double) -> AsyncStream<SensorReading> {
        let (stream, continuation) = AsyncStream.makeStream(of: SensorReading.self, bufferingPolicy: .unbounded)
        let task = Task {
            let clock = ContinuousClock()
            // Schedule each reading relative to the start so delays don't accumulate.
            let start = clock.now
            let firstTimestamp = readings.first?.timestamp
            for reading in readings {
                if Task.isCancelled {
                    break
                }
                if speed > 0, let firstTimestamp {
                    let offset = reading.timestamp.timeIntervalSince(firstTimestamp) / speed
                    // try? because sleep only throws on cancellation, which the loop checks anyway.
                    try? await clock.sleep(until: start.advanced(by: .seconds(offset)))
                }
                continuation.yield(reading)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
