/// What one upload pass did, for logging and tests.
public struct UploadReport: Hashable, Sendable {
    /// Batches the backend now has (accepted or already received).
    public var sent = 0
    /// Batches still waiting, to retry later.
    public var kept = 0
    /// Batches older than 30 days, given up on.
    public var dropped = 0

    public init(sent: Int = 0, kept: Int = 0, dropped: Int = 0) {
        self.sent = sent
        self.kept = kept
        self.dropped = dropped
    }
}
