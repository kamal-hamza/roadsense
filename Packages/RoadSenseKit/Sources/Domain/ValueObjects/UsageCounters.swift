import Foundation

/// What's uploaded when data sharing is off: anonymous counts, with no places or hotspots.
public struct UsageCounters: Identifiable, Hashable, Sendable, Codable {
    /// Random per upload, so the backend can drop duplicates.
    public let id: UUID
    /// When the drive started, rounded down to the hour.
    public let hour: Date
    public let warningsShown: Int
    public let warningsSuppressed: Int
    public let mutes: Int
    public let hotspotsPassed: Int

    public init(id: UUID, hour: Date, warningsShown: Int, warningsSuppressed: Int, mutes: Int, hotspotsPassed: Int) {
        self.id = id
        self.hour = hour
        self.warningsShown = warningsShown
        self.warningsSuppressed = warningsSuppressed
        self.mutes = mutes
        self.hotspotsPassed = hotspotsPassed
    }
}
