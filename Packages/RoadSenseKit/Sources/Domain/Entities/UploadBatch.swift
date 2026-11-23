import Foundation

/// What a batch carries: full events when data sharing is on, only counts when it's off.
public enum UploadContent: Hashable, Sendable, Codable {
    case events([UploadEvent])
    case counters(UsageCounters)
}

/// A queued upload. It isn't a trip: events carry no trip id, and a batch can mix drives.
public struct UploadBatch: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let deviceID: DeviceID
    public let createdAt: Date
    public let content: UploadContent

    public init(id: UUID, deviceID: DeviceID, createdAt: Date, content: UploadContent) {
        self.id = id
        self.deviceID = deviceID
        self.createdAt = createdAt
        self.content = content
    }

    /// Whether the batch has waited in the queue too long and should be dropped (30 days by default).
    public func isExpired(at now: Date, maximumAge: TimeInterval = 30 * 24 * 60 * 60) -> Bool {
        now.timeIntervalSince(createdAt) > maximumAge
    }
}
