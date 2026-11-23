import Foundation
import SensorCore

/// Everything logged during one drive. It stays on the phone; only trimmed events are uploaded.
public struct TripLog: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let startedAt: Date
    /// Where the drive started, used to hide the start area before uploading.
    public let startCoordinate: Coordinate?
    public private(set) var entries: [TripLogEntry]
    public private(set) var endedAt: Date?
    public private(set) var endReason: TripEndReason?
    /// Where the drive ended, used to hide the end area before uploading.
    public private(set) var endCoordinate: Coordinate?

    public var isFinished: Bool {
        endReason != nil
    }

    public init(id: UUID = UUID(), startedAt: Date, startCoordinate: Coordinate?, entries: [TripLogEntry] = []) {
        self.id = id
        self.startedAt = startedAt
        self.startCoordinate = startCoordinate
        self.entries = entries
    }

    /// Adds an entry. Feedback can still be added after the drive has finished.
    public mutating func append(_ entry: TripLogEntry) {
        entries.append(entry)
    }

    /// Marks the drive as over.
    /// - Throws: `TripLogError` if it already finished or `time` is before the start.
    public mutating func finish(at time: Date, reason: TripEndReason, endCoordinate: Coordinate?) throws(TripLogError) {
        guard !isFinished else { throw .alreadyFinished }
        guard time >= startedAt else { throw .endsBeforeStart }
        endedAt = time
        endReason = reason
        // An app killed mid-drive has no final fix, so fall back to the last place we logged.
        self.endCoordinate = endCoordinate ?? entries.last(where: { $0.coordinate != nil })?.coordinate
    }
}
