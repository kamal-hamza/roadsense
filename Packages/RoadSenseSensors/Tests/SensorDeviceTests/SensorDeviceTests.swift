import DriveSimulation
import Foundation
import SensorCore
import SensorDevice
import SensorRecording
import Testing

struct FileSensorLogStoreTests {
    private let readings = SyntheticDrive(segments: [.parked(seconds: 1), .accelerate(g: 0.2, seconds: 2)]).readings()

    @Test func `writes a log that reads back`() async throws {
        let store = FileSensorLogStore(directory: temporaryDirectory())
        let id = UUID()
        #expect(await store.logURL(recordingID: id) == nil)

        try await store.beginLog(recordingID: id)
        try await store.append(Array(readings.prefix(50)))
        try await store.append(Array(readings.dropFirst(50)))
        try await store.finishLog()

        let url = try #require(await store.logURL(recordingID: id))
        let decoded = try FileSensorLogStore.readLog(at: url)
        #expect(decoded.count == readings.count)
        for (original, roundTripped) in zip(readings, decoded) {
            #expect(abs(original.timestamp.timeIntervalSince(roundTripped.timestamp)) < 1e-5)
            #expect(original.kindName == roundTripped.kindName)
        }
    }

    @Test func `ignores appends when no log is open`() async throws {
        let store = FileSensorLogStore(directory: temporaryDirectory())

        try await store.append(readings)

        #expect(await store.logURL(recordingID: UUID()) == nil)
    }
}

struct ReplaySensorSourceTests {
    @Test func `replays every reading in order`() async {
        let readings = SyntheticDrive(segments: [.parked(seconds: 1), .cruise(seconds: 1)]).readings()
        let source = ReplaySensorSource(readings: readings, speed: 0)

        var replayed: [SensorReading] = []
        for await reading in await source.readings(configuration: SensorConfiguration()) {
            replayed.append(reading)
        }

        #expect(replayed == readings)
    }

    @Test func `simulated drives start now`() async {
        let source = SimulatedSensorSource(repetitions: 1)

        var first: [SensorReading] = []
        for await reading in await source.readings(configuration: SensorConfiguration()) {
            first.append(reading)
            if first.count == 5 {
                break
            }
        }

        #expect(first.count == 5)
        #expect(abs(first[0].timestamp.timeIntervalSinceNow) < 5)
    }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "Sensor Device Tests-\(UUID().uuidString)")
}

private extension SensorReading {
    var kindName: String {
        switch self {
        case .motion: "motion"
        case .location: "location"
        case .activity: "activity"
        case .locationStatus: "locationStatus"
        }
    }
}
