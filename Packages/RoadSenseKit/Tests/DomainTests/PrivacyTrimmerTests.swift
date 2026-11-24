import Domain
import Foundation
import SensorCore
import Testing

struct PrivacyTrimmerTests {
    /// A finished 2 km drive from the origin north, with the given entries.
    private func log(_ entries: [TripLogEntry]) throws -> TripLog {
        var log = TripLog(startedAt: Fixtures.start, startCoordinate: Fixtures.point(0), entries: entries)
        try log.finish(
            at: Fixtures.start.addingTimeInterval(300),
            reason: .arrived,
            endCoordinate: Fixtures.point(2000),
        )
        return log
    }

    private func passed(at meters: Double?, time: TimeInterval = 100) -> TripLogEntry {
        TripLogEntry(
            timestamp: Fixtures.start.addingTimeInterval(time),
            coordinate: meters.map { Fixtures.point($0) },
            event: .hotspotPassed(hotspotID: UUID(), outcome: .missed, brakedHard: false),
        )
    }

    @Test(arguments: [(150.0, false), (199, false), (201, true), (1000, true), (1801, false), (1850, false)])
    func `drops events within 200 m of the start or end`(meters: Double, isKept: Bool) throws {
        let events = try PrivacyTrimmer().events(from: log([passed(at: meters)]))

        #expect(events.isEmpty == !isKept)
    }

    @Test func `keeps events with no place`() throws {
        let entry = TripLogEntry(timestamp: Fixtures.start, coordinate: nil, event: .muted)

        let events = try PrivacyTrimmer().events(from: log([entry]))

        #expect(events.map(\.event) == [.muted])
    }

    @Test func `drops everything with a place if an endpoint is unknown`() {
        let log = TripLog(startedAt: Fixtures.start, startCoordinate: nil, entries: [passed(at: 1000)])

        #expect(PrivacyTrimmer().events(from: log).isEmpty)
    }

    @Test func `removes trace fixes near the start from a kept hard brake`() throws {
        let record = HardBrakeRecord(
            course: 0,
            speedBefore: 15,
            speedAfter: 5,
            peakDeceleration: 0.5,
            nearestHotspotID: nil,
            wasWarned: false,
            secondsSinceWarning: nil,
            trace: [180.0, 210, 240].map { TracePoint(coordinate: Fixtures.point($0), course: 0) },
        )
        let entry = TripLogEntry(timestamp: Fixtures.start, coordinate: Fixtures.point(220), event: .hardBrake(record))

        let event = try #require(PrivacyTrimmer().events(from: log([entry])).first?.event)

        guard case let .hardBrake(trimmed) = event else {
            Issue.record("Expected a hard brake, got \(event)")
            return
        }
        #expect(trimmed.trace.map(\.coordinate) == [Fixtures.point(210), Fixtures.point(240)])
    }

    @Test func `removes trace fixes near the start from a kept sharp turn`() throws {
        let record = SharpTurnRecord(
            peakLateralAcceleration: 0.4,
            nearestHotspotID: UUID(),
            trace: [180.0, 210, 240].map { TracePoint(coordinate: Fixtures.point($0), course: 0) },
        )
        let entry = TripLogEntry(timestamp: Fixtures.start, coordinate: Fixtures.point(220), event: .sharpTurn(record))

        let event = try #require(PrivacyTrimmer().events(from: log([entry])).first?.event)

        guard case let .sharpTurn(trimmed) = event else {
            Issue.record("Expected a sharp turn, got \(event)")
            return
        }
        #expect(trimmed.trace.map(\.coordinate) == [Fixtures.point(210), Fixtures.point(240)])
    }

    @Test func `drops sharp turns that weren't near a hotspot`() throws {
        let away = SharpTurnRecord(
            peakLateralAcceleration: 0.4,
            nearestHotspotID: nil,
            trace: [TracePoint(coordinate: Fixtures.point(1000), course: 0)],
        )
        let entry = TripLogEntry(timestamp: Fixtures.start, coordinate: Fixtures.point(1000), event: .sharpTurn(away))

        #expect(try PrivacyTrimmer().events(from: log([entry])).isEmpty)
    }

    @Test func `rounds times down to the hour and gives every event a fresh id`() throws {
        // 800_000_000 s after 2001-01-01 is 30 minutes past an hour in UTC; +100 s stays in that hour.
        let ids = [UUID(), UUID()]
        var remaining = ids

        let events = try PrivacyTrimmer().events(
            from: log([passed(at: 500), passed(at: 600)]),
            makeID: { remaining.removeFirst() },
        )

        #expect(events.map(\.id) == ids)
        let hour = try #require(events.first?.hour.timeIntervalSince1970)
        #expect(hour.truncatingRemainder(dividingBy: 3600) == 0)
        #expect(Fixtures.start.addingTimeInterval(100).timeIntervalSince1970 - hour < 3600)
    }

    @Test func `counters carry no places or hotspots`() throws {
        let entries = [
            TripLogEntry(timestamp: Fixtures.start, coordinate: nil, event: .muted),
            passed(at: 1000),
            TripLogEntry(
                timestamp: Fixtures.start,
                coordinate: Fixtures.point(900),
                event: .warningShown(hotspotIDs: [UUID()], speed: 12),
            ),
        ]

        let counters = try PrivacyTrimmer().counters(from: log(entries))

        #expect(counters.mutes == 1)
        #expect(counters.hotspotsPassed == 1)
        #expect(counters.warningsShown == 1)
        #expect(counters.warningsSuppressed == 0)
    }
}

struct UploadBatchTests {
    @Test(arguments: [(29.0, false), (31, true)])
    func `expires after 30 days`(days: Double, isExpired: Bool) {
        let batch = UploadBatch(
            id: UUID(),
            deviceID: DeviceID(rawValue: UUID()),
            createdAt: Fixtures.start,
            content: .events([]),
        )

        #expect(batch.isExpired(at: Fixtures.start.addingTimeInterval(days * 86400)) == isExpired)
    }
}
