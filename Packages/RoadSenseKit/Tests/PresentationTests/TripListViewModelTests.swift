import Application
import Domain
import Foundation
@testable import Presentation
import Testing

struct TripListViewModelTests {
    @Test func `load publishes trips`() async throws {
        let trip = try Trip(name: "Commute", startedAt: .now, distance: .init(value: 5, unit: .kilometers))
        let viewModel =
            TripListViewModel(listTrips: ListTripsUseCase(repository: FakeTripRepository(result: .success([trip]))))

        await viewModel.load()

        #expect(viewModel.state == .loaded([trip]))
    }

    @Test func `load publishes failure`() async {
        let viewModel = TripListViewModel(
            listTrips: ListTripsUseCase(repository: FakeTripRepository(result: .failure(FakeError()))),
        )

        await viewModel.load()

        guard case .failed = viewModel.state else {
            Issue.record("Expected .failed, got \(viewModel.state)")
            return
        }
    }
}

private struct FakeError: Error {}

private struct FakeTripRepository: TripRepository {
    var result: Result<[Trip], any Error>

    func allTrips() async throws -> [Trip] {
        try result.get()
    }

    func save(_: Trip) async throws {}
}
