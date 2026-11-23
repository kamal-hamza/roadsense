import Foundation

/// The driver's answer to "Were the warnings helpful?".
public enum WarningFeedback: Hashable, Sendable, Codable {
    case helpful
    /// The driver picked the warning that wasn't useful.
    case notHelpful(hotspotID: UUID)
}
