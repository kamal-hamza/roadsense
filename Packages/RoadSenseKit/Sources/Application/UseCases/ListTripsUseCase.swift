import Domain
import Foundation

/// Returns all recorded trips, most recent first.
public struct ListTripsUseCase: Sendable {
    private let repository: any TripRepository

    public init(repository: any TripRepository) {
        self.repository = repository
    }

    public func callAsFunction() async throws -> [Trip] {
        try await repository.allTrips().sorted { $0.startedAt > $1.startedAt }
    }
}
