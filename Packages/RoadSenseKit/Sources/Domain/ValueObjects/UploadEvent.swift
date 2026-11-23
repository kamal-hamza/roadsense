import Foundation

/// One event ready to upload: its own random id, the hour it happened, and no trip id or route.
public struct UploadEvent: Identifiable, Hashable, Sendable, Codable {
    /// Random per event and never reused; the backend uses it to drop duplicates.
    public let id: UUID
    /// When it happened, rounded down to the hour.
    public let hour: Date
    public let event: TripLogEvent

    public init(id: UUID, hour: Date, event: TripLogEvent) {
        self.id = id
        self.hour = hour
        self.event = event
    }
}
