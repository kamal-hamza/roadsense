import Foundation

/// Something that happened during a drive, kept for the summary and the success metrics.
public enum TripLogEvent: Hashable, Sendable, Codable {
    case hardBrake(HardBrakeRecord)
    /// Every sharp turn, for the summary; only ones near a hotspot are uploaded.
    case sharpTurn(SharpTurnRecord)
    case hotspotPassed(hotspotID: UUID, outcome: HotspotPassOutcome, brakedHard: Bool)
    case warningShown(hotspotIDs: [UUID], speed: Double?)
    case warningSuppressed(hotspotIDs: [UUID])
    case muted
    case unmuted
    case feedback(WarningFeedback)
}
