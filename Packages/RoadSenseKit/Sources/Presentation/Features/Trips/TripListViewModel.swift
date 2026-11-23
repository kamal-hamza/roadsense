import Application
import Domain
import Foundation
import Observation

/// State and actions for `TripListView`.
@Observable
final class TripListViewModel {
    enum State: Equatable {
        case loading
        case loaded([Trip])
        case failed(message: String)
    }

    private(set) var state: State = .loading

    private let listTrips: ListTripsUseCase

    init(listTrips: ListTripsUseCase) {
        self.listTrips = listTrips
    }

    /// Loads trips, most recent first, keeping the current list visible while reloading.
    func load() async {
        do {
            state = try await .loaded(listTrips())
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }
}
