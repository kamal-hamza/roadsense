import DriveSimulation
import Foundation
import SensorCore
import SensorRecording
import Testing

struct SensorRecorderTests {
    private let drive = SyntheticDrive(
        segments: DriveSegment.warmUp + [.brake(g: 0.45, seconds: 1.5), .cruise(seconds: 4)],
    )

    @Test func `records events, distance, and the raw log`() async throws {
        let readings = drive.readings()
        let logStore = MemorySensorLogStore()
        let recorder = SensorRecorder(sensorSource: StubSensorSource(readings: readings), sensorLogStore: logStore)

        let snapshots = try await recorder.start(options: .init(logsRawSensors: true))
        var lastSnapshot: RecordingSnapshot?
        // // The stub stream finishes after the last reading, so this loop ends on its own.
        for await snapshot in snapshots {
            lastSnapshot = snapshot
        }
        let summary = try await recorder.stop()

        #expect(summary.events.map(\.kind) == [.hardBrake])
        #expect(summary.distanceMeters > 300)
        #expect(lastSnapshot?.recordingID == summary.id)
        #expect(lastSnapshot?.isFrameReady == true)
        #expect(await logStore.loggedReadings == readings)
        #expect(await logStore.isOpen == false)
    }

    @Test func `snapshots carry the latest GPS fix`() async throws {
        let recorder = SensorRecorder(
            sensorSource: StubSensorSource(readings: drive.readings()),
            sensorLogStore: MemorySensorLogStore(),
        )

        var lastSnapshot: RecordingSnapshot?
        for await snapshot in try await recorder.start() {
            lastSnapshot = snapshot
        }
        _ = try await recorder.stop()

        let location = try #require(lastSnapshot?.location)
        #expect(location.speed != nil)
        // The last snapshot is stamped with the last reading's sensor time, not the wall clock.
        #expect(lastSnapshot?.timestamp == drive.readings().last?.timestamp)
    }

    @Test func `uses the detection thresholds it's given`() async throws {
        let recorder = SensorRecorder(
            sensorSource: StubSensorSource(readings: drive.readings()),
            sensorLogStore: MemorySensorLogStore(),
        )
        var strict = DetectionPipeline.Configuration()
        // The drive brakes at 0.45 g, so a 0.6 g rule should ignore it.
        strict.hardBrakeThreshold = 0.6

        for await _ in try await recorder.start(options: .init(detection: strict)) {}
        let summary = try await recorder.stop()

        #expect(summary.events.isEmpty)
    }

    @Test func `can't start twice`() async throws {
        let recorder = SensorRecorder(
            sensorSource: StubSensorSource(readings: []),
            sensorLogStore: MemorySensorLogStore(),
        )

        _ = try await recorder.start()

        await #expect(throws: SensorRecorderError.alreadyRecording) {
            _ = try await recorder.start()
        }
    }

    @Test func `can't stop when not recording`() async {
        let recorder = SensorRecorder(
            sensorSource: StubSensorSource(readings: []),
            sensorLogStore: MemorySensorLogStore(),
        )

        await #expect(throws: SensorRecorderError.notRecording) {
            _ = try await recorder.stop()
        }
    }
}

private struct StubSensorSource: SensorSource {
    let readings: [SensorReading]

    func readings(configuration _: SensorConfiguration) async -> AsyncStream<SensorReading> {
        // // Push every reading at once, then finish, like a replayed log with no delays.
        AsyncStream { continuation in
            for reading in readings {
                continuation.yield(reading)
            }
            continuation.finish()
        }
    }
}

private actor MemorySensorLogStore: SensorLogStore {
    private(set) var loggedReadings: [SensorReading] = []
    private(set) var isOpen = false

    func beginLog(recordingID _: UUID) {
        isOpen = true
    }

    func append(_ readings: [SensorReading]) {
        loggedReadings.append(contentsOf: readings)
    }

    func finishLog() {
        isOpen = false
    }

    func logURL(recordingID _: UUID) -> URL? {
        nil
    }
}
