import Domain
import Foundation
import SensorCore
import Testing

struct TripLogTests {
    private func entry(_ event: TripLogEvent, at meters: Double? = 500, time: TimeInterval = 60) -> TripLogEntry {
        TripLogEntry(
            timestamp: Fixtures.start.addingTimeInterval(time),
            coordinate: meters.map { Fixtures.point($0) },
            event: event,
        )
    }

    private func brake(nearHotspot hotspotID: UUID?) -> TripLogEvent {
        .hardBrake(HardBrakeRecord(
            course: 0,
            speedBefore: 20,
            speedAfter: 8,
            peakDeceleration: 0.45,
            nearestHotspotID: hotspotID,
            wasWarned: hotspotID != nil,
            secondsSinceWarning: hotspotID == nil ? nil : 6,
            trace: [],
        ))
    }

    @Test func `finishing records the end and falls back to the last logged place`() throws {
        var log = TripLog(startedAt: Fixtures.start, startCoordinate: Fixtures.point(0))
        log.append(entry(.muted, at: 900))

        try log.finish(at: Fixtures.start.addingTimeInterval(600), reason: .incomplete, endCoordinate: nil)

        #expect(log.isFinished)
        #expect(log.endReason == .incomplete)
        #expect(log.endCoordinate == Fixtures.point(900))
    }

    @Test func `can't finish twice or before the start`() throws {
        var log = TripLog(startedAt: Fixtures.start, startCoordinate: nil)

        #expect(throws: TripLogError.endsBeforeStart) {
            try log.finish(at: Fixtures.start.addingTimeInterval(-1), reason: .arrived, endCoordinate: nil)
        }
        try log.finish(at: Fixtures.start, reason: .arrived, endCoordinate: nil)
        #expect(throws: TripLogError.alreadyFinished) {
            try log.finish(at: Fixtures.start, reason: .arrived, endCoordinate: nil)
        }
    }

    @Test func `round-trips through JSON`() throws {
        var log = TripLog(startedAt: Fixtures.start, startCoordinate: Fixtures.point(0))
        log.append(entry(.hotspotPassed(hotspotID: UUID(), outcome: .warned(secondsOfWarning: 7.5), brakedHard: true)))
        log.append(entry(.feedback(.notHelpful(hotspotID: UUID())), at: nil))
        try log.finish(
            at: Fixtures.start.addingTimeInterval(600),
            reason: .arrived,
            endCoordinate: Fixtures.point(2000),
        )

        let decoded = try JSONDecoder().decode(TripLog.self, from: JSONEncoder().encode(log))

        #expect(decoded == log)
    }

    @Test func `summary counts passes, warnings, brakes near hotspots, and sharp turns`() {
        let first = UUID()
        let second = UUID()
        var log = TripLog(startedAt: Fixtures.start, startCoordinate: Fixtures.point(0))
        log.append(entry(.warningShown(hotspotIDs: [first, second], speed: 15)))
        log.append(entry(.warningShown(hotspotIDs: [second], speed: 15)))
        log.append(entry(.warningSuppressed(hotspotIDs: [UUID()])))
        log.append(entry(brake(nearHotspot: first)))
        log.append(entry(brake(nearHotspot: nil)))
        log.append(entry(.sharpTurn(SharpTurnRecord(peakLateralAcceleration: 0.4, nearestHotspotID: nil, trace: []))))
        log.append(entry(.hotspotPassed(hotspotID: first, outcome: .warned(secondsOfWarning: 8), brakedHard: true)))
        log.append(entry(.hotspotPassed(hotspotID: second, outcome: .missed, brakedHard: false)))

        let summary = TripSummary(log: log)

        #expect(summary.hotspotsPassed == 2)
        #expect(summary.warningsGiven == 2)
        #expect(summary.hardBrakes == 2)
        #expect(summary.hardBrakesNearHotspots == 1)
        #expect(summary.sharpTurns == 1)
        #expect(summary.warnedHotspotIDs == [first, second])
        #expect(summary.asksForFeedback)
    }

    @Test func `no warnings means no feedback question`() {
        let summary = TripSummary(log: TripLog(startedAt: Fixtures.start, startCoordinate: nil))

        #expect(!summary.asksForFeedback)
    }
}
