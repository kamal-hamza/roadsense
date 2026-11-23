import Application
import Domain
import Foundation
@testable import Infrastructure
import SensorCore
import Testing

struct FileTripLogStoreTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let here = Coordinate(latitude: 47.6, longitude: -122.3)

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "FileTripLogStoreTests-\(UUID().uuidString)")
    }

    private func entry(_ seconds: TimeInterval) -> TripLogEntry {
        TripLogEntry(
            timestamp: start.addingTimeInterval(seconds),
            coordinate: here,
            event: .hotspotPassed(hotspotID: UUID(), outcome: .warned(secondsOfWarning: 8), brakedHard: false),
        )
    }

    @Test func `an open log survives the app being closed`() async throws {
        let directory = temporaryDirectory()
        let log = TripLog(startedAt: start, startCoordinate: here)
        let store = FileTripLogStore(directory: directory)
        try await store.begin(log)
        try await store.append(entry(10))
        try await store.append(entry(20))

        // A new store, like after a relaunch, reads it back from disk.
        let recovered = try await FileTripLogStore(directory: directory).unfinishedLog()

        #expect(recovered?.id == log.id)
        #expect(recovered?.entries.map(\.timestamp) == [start.addingTimeInterval(10), start.addingTimeInterval(20)])
    }

    @Test func `a line cut off mid-write is skipped`() async throws {
        let directory = temporaryDirectory()
        let store = FileTripLogStore(directory: directory)
        try await store.begin(TripLog(startedAt: start, startCoordinate: here))
        try await store.append(entry(10))
        let handle = try FileHandle(forWritingTo: directory.appending(path: "open.jsonl"))
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("{\"entry\":{\"timest".utf8))
        try handle.close()

        let recovered = try await FileTripLogStore(directory: directory).unfinishedLog()

        #expect(recovered?.entries.count == 1)
    }

    @Test func `finishing saves the whole log and clears the open one`() async throws {
        let directory = temporaryDirectory()
        let log = TripLog(startedAt: start, startCoordinate: here)
        let store = FileTripLogStore(directory: directory)
        try await store.begin(log)
        try await store.append(entry(10))

        try await store.finish(at: start.addingTimeInterval(600), reason: .arrived, endCoordinate: here)

        #expect(try await store.unfinishedLog() == nil)
        let saved = try JSONDecoder().decode(TripLog.self, from: Data(contentsOf: store.finishedLogURL(id: log.id)))
        #expect(saved.endReason == .arrived)
        #expect(saved.entries.count == 1)
    }

    @Test func `finished logs can be listed, replaced, and deleted`() async throws {
        let store = FileTripLogStore(directory: temporaryDirectory())
        let first = TripLog(startedAt: start, startCoordinate: here)
        let second = TripLog(startedAt: start.addingTimeInterval(3600), startCoordinate: here)
        for log in [second, first] {
            try await store.begin(log)
            try await store.finish(at: log.startedAt.addingTimeInterval(60), reason: .arrived, endCoordinate: here)
        }
        var withFeedback = try #require(try await store.finishedLogs().first)
        withFeedback.append(TripLogEntry(
            timestamp: start.addingTimeInterval(90),
            coordinate: nil,
            event: .feedback(.helpful),
        ))

        try await store.saveFinished(withFeedback)
        let afterSave = try await store.finishedLogs()
        try await store.deleteFinished(id: first.id)
        try await store.deleteFinished(id: first.id)
        let afterDelete = try await store.finishedLogs()

        #expect(afterSave.map(\.id) == [first.id, second.id])
        #expect(afterSave.first?.entries.last?.event == .feedback(.helpful))
        #expect(afterDelete.map(\.id) == [second.id])
    }

    @Test func `nothing is open on a fresh install`() async throws {
        #expect(try await FileTripLogStore(directory: temporaryDirectory()).unfinishedLog() == nil)
    }
}

struct SystemDriveAlerterTests {
    private func warning(_ kinds: [HotspotKind], distance: Double) -> DriveWarning {
        let hotspots = kinds.map { kind in
            RouteHotspot(
                hotspot: Hotspot(
                    id: UUID(),
                    kind: kind,
                    coordinate: Coordinate(latitude: 0, longitude: 0),
                    bearing: Bearing(degrees: 0),
                    driverCount: 5,
                ),
                distanceAlongRoute: 0,
            )
        }
        return DriveWarning(hotspots: hotspots, distance: distance, speed: 20, isSuppressed: false, timestamp: .now)
    }

    @Test func `names one hazard, rounded to 50 meters`() {
        let phrase = SystemDriveAlerter.phrase(
            for: warning([.sharpCurve], distance: 187),
            locale: Locale(identifier: "en_AU"),
        )

        #expect(phrase == "Sharp curve in 200 metres")
    }

    @Test func `counts grouped hazards`() {
        let phrase = SystemDriveAlerter.phrase(
            for: warning([.sharpCurve, .shortMerge], distance: 140),
            locale: Locale(identifier: "en_AU"),
        )

        #expect(phrase == "2 hazards ahead in 150 metres")
    }

    @Test func `uses the driver's units`() {
        let phrase = SystemDriveAlerter.phrase(
            for: warning([.suddenStop], distance: 300),
            locale: Locale(identifier: "en_US"),
        )

        #expect(phrase.hasPrefix("Sudden stops ahead in"))
        #expect(phrase.contains("feet"))
    }
}
