import Domain
import Foundation

/// On launch, closes a drive that was cut off (app closed, battery died) as "incomplete".
public struct RecoverIncompleteTripUseCase: Sendable {
    private let tripLogStore: any TripLogStore

    public init(tripLogStore: any TripLogStore) {
        self.tripLogStore = tripLogStore
    }

    /// Closes the unfinished log, if there is one, and returns it.
    public func callAsFunction() async throws -> TripLog? {
        guard var log = try await tripLogStore.unfinishedLog() else { return nil }
        // The last entry is the closest we have to when the drive stopped.
        let endedAt = log.entries.last?.timestamp ?? log.startedAt
        try log.finish(at: max(endedAt, log.startedAt), reason: .incomplete, endCoordinate: nil)
        try await tripLogStore.finish(at: log.endedAt ?? endedAt, reason: .incomplete, endCoordinate: log.endCoordinate)
        return log
    }
}
