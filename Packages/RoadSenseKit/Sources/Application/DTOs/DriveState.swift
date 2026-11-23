import Domain

/// The drive as the UI sees it: still going, or over with its log.
public enum DriveState: Hashable, Sendable {
    case driving(DriveUpdate)
    case ended(TripLog)
}
