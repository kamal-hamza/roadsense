import Domain
import Foundation

/// Records the driver's answer to "Were the warnings helpful?" in the finished trip log.
public struct SubmitTripFeedbackUseCase: Sendable {
    private let tripLogStore: any TripLogStore
    private let now: @Sendable () -> Date

    public init(tripLogStore: any TripLogStore, now: @escaping @Sendable () -> Date = Date.init) {
        self.tripLogStore = tripLogStore
        self.now = now
    }

    /// Adds `feedback` to `log`, saves it, and returns the updated log.
    public func callAsFunction(_ feedback: WarningFeedback, for log: TripLog) async throws -> TripLog {
        var updated = log
        // Feedback has no place, so privacy trimming always keeps it.
        updated.append(TripLogEntry(timestamp: now(), coordinate: nil, event: .feedback(feedback)))
        try await tripLogStore.saveFinished(updated)
        return updated
    }
}
