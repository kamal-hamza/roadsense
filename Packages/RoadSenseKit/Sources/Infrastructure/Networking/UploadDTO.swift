import Domain
import Foundation
import SensorCore

// Wire format for `POST /v1/events`. Matches server/crates/api/src/dto.rs: no trip id, no route.

/// One upload: events, or only counters when data sharing is off.
struct UploadRequestDTO: Encodable {
    let batchId: UUID
    let createdAt: Date
    let events: [EventDTO]?
    let counters: CountersDTO?

    init(_ batch: UploadBatch) {
        batchId = batch.id
        createdAt = batch.createdAt
        switch batch.content {
        case let .events(events):
            self.events = events.map(EventDTO.init)
            counters = nil
        case let .counters(counters):
            events = nil
            self.counters = CountersDTO(counters)
        }
    }
}

/// An event as `{"id", "hour", "type", ...fields}`.
struct EventDTO: Encodable {
    let upload: UploadEvent

    private enum Keys: String, CodingKey {
        case id, hour, type
        case course, speedBefore, speedAfter, peakDeceleration, nearestHotspotId, wasWarned, secondsSinceWarning, trace
        case peakLateralAcceleration
        case hotspotId, outcome, secondsOfWarning, brakedHard
        case hotspotIds, speed
        case helpful
    }

    private struct TracePointDTO: Encodable {
        let latitude: Double
        let longitude: Double
        let course: Double?

        init(_ point: TracePoint) {
            latitude = point.coordinate.latitude
            longitude = point.coordinate.longitude
            course = point.course
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(upload.id, forKey: .id)
        try container.encode(upload.hour, forKey: .hour)
        switch upload.event {
        case let .hardBrake(record):
            try encodeHardBrake(record, into: &container)
        case let .sharpTurn(record):
            try container.encode("sharpTurn", forKey: .type)
            try container.encode(record.peakLateralAcceleration, forKey: .peakLateralAcceleration)
            try container.encode(record.trace.map(TracePointDTO.init), forKey: .trace)
        case let .hotspotPassed(hotspotID, outcome, brakedHard):
            try encodePass(hotspotID: hotspotID, outcome: outcome, brakedHard: brakedHard, into: &container)
        case let .warningShown(hotspotIDs, speed):
            try container.encode("warningShown", forKey: .type)
            try container.encode(hotspotIDs, forKey: .hotspotIds)
            try container.encodeIfPresent(speed, forKey: .speed)
        case let .warningSuppressed(hotspotIDs):
            try container.encode("warningSuppressed", forKey: .type)
            try container.encode(hotspotIDs, forKey: .hotspotIds)
        case .muted:
            try container.encode("muted", forKey: .type)
        case .unmuted:
            try container.encode("unmuted", forKey: .type)
        case .feedback(.helpful):
            try container.encode("feedback", forKey: .type)
            try container.encode(true, forKey: .helpful)
        case let .feedback(.notHelpful(hotspotID)):
            try container.encode("feedback", forKey: .type)
            try container.encode(false, forKey: .helpful)
            try container.encode(hotspotID, forKey: .hotspotId)
        }
    }

    private func encodeHardBrake(_ record: HardBrakeRecord, into container: inout KeyedEncodingContainer<Keys>) throws {
        try container.encode("hardBrake", forKey: .type)
        try container.encodeIfPresent(record.course, forKey: .course)
        try container.encodeIfPresent(record.speedBefore, forKey: .speedBefore)
        try container.encodeIfPresent(record.speedAfter, forKey: .speedAfter)
        try container.encode(record.peakDeceleration, forKey: .peakDeceleration)
        try container.encodeIfPresent(record.nearestHotspotID, forKey: .nearestHotspotId)
        try container.encode(record.wasWarned, forKey: .wasWarned)
        try container.encodeIfPresent(record.secondsSinceWarning, forKey: .secondsSinceWarning)
        try container.encode(record.trace.map(TracePointDTO.init), forKey: .trace)
    }

    private func encodePass(
        hotspotID: UUID,
        outcome: HotspotPassOutcome,
        brakedHard: Bool,
        into container: inout KeyedEncodingContainer<Keys>,
    ) throws {
        try container.encode("hotspotPassed", forKey: .type)
        try container.encode(hotspotID, forKey: .hotspotId)
        try container.encode(brakedHard, forKey: .brakedHard)
        switch outcome {
        case let .warned(seconds):
            try container.encode("warned", forKey: .outcome)
            try container.encode(seconds, forKey: .secondsOfWarning)
        case .suppressed:
            try container.encode("suppressed", forKey: .outcome)
        case .missed:
            try container.encode("missed", forKey: .outcome)
        }
    }
}

struct CountersDTO: Encodable {
    let id: UUID
    let hour: Date
    let warningsShown: Int
    let warningsSuppressed: Int
    let mutes: Int
    let hotspotsPassed: Int

    init(_ counters: UsageCounters) {
        id = counters.id
        hour = counters.hour
        warningsShown = counters.warningsShown
        warningsSuppressed = counters.warningsSuppressed
        mutes = counters.mutes
        hotspotsPassed = counters.hotspotsPassed
    }
}
