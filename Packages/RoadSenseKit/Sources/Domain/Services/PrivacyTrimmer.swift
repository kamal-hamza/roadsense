import Foundation
import SensorCore

/// Turns a finished trip log into upload-safe data. See docs/MVP_USE_CASE_1.md §4.2 and §5.2.
public struct PrivacyTrimmer: Sendable {
    /// Events this close to where the drive started or ended are dropped, so home and work stay hidden.
    public var endpointRadius = 200.0

    public init() {}

    /// The log's events with places near the start and end removed, times rounded, and fresh random ids.
    public func events(from log: TripLog, makeID: () -> UUID = UUID.init) -> [UploadEvent] {
        log.entries.compactMap { entry -> UploadEvent? in
            guard let event = trimmed(entry, in: log) else { return nil }
            return UploadEvent(id: makeID(), hour: Self.hour(of: entry.timestamp), event: event)
        }
    }

    /// Anonymous counts for when data sharing is off.
    public func counters(from log: TripLog, makeID: () -> UUID = UUID.init) -> UsageCounters {
        var shown = 0
        var suppressed = 0
        var mutes = 0
        var passed = 0
        for entry in log.entries {
            switch entry.event {
            case .warningShown: shown += 1
            case .warningSuppressed: suppressed += 1
            case .muted: mutes += 1
            case .hotspotPassed: passed += 1
            case .hardBrake, .unmuted, .feedback: break
            }
        }
        return UsageCounters(
            id: makeID(),
            hour: Self.hour(of: log.startedAt),
            warningsShown: shown,
            warningsSuppressed: suppressed,
            mutes: mutes,
            hotspotsPassed: passed,
        )
    }

    /// The event to upload for `entry`, or `nil` if it would reveal the start or end area.
    private func trimmed(_ entry: TripLogEntry, in log: TripLog) -> TripLogEvent? {
        // Events with no place (mute, feedback) can't reveal where someone lives.
        guard let coordinate = entry.coordinate else { return entry.event }
        guard !isNearEndpoint(coordinate, of: log) else { return nil }
        // A brake just outside the radius can still have trace fixes inside it, so drop those too.
        if case let .hardBrake(record) = entry.event {
            let trace = record.trace.filter { !isNearEndpoint($0.coordinate, of: log) }
            return .hardBrake(record.withTrace(trace))
        }
        return entry.event
    }

    private func isNearEndpoint(_ coordinate: Coordinate, of log: TripLog) -> Bool {
        // If we don't know an endpoint, we can't prove an event is far from it, so treat it as near.
        guard let start = log.startCoordinate, let end = log.endCoordinate else { return true }
        return coordinate.distance(to: start) <= endpointRadius || coordinate.distance(to: end) <= endpointRadius
    }

    /// `date` rounded down to the start of its hour (UTC).
    private static func hour(of date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (seconds / 3600).rounded(.down) * 3600)
    }
}
