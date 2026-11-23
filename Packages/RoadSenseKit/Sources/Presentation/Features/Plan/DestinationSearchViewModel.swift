import Application
import Domain
import Foundation
import Observation

/// State and actions for `DestinationSearchView` (activity diagram 1, place search).
@Observable
final class DestinationSearchViewModel {
    enum State: Equatable {
        case idle
        case searching
        case results([Place])
        case noMatches
        case failed(PlanningFailure)
    }

    /// What the driver has typed so far.
    var query = ""
    private(set) var state: State = .idle
    /// Bumped on each submit; the view restarts its search task when it changes.
    private(set) var submissionCount = 0
    /// A place to go to next: the one the driver tapped, or the only match.
    private(set) var selection: Place?

    @ObservationIgnored private let searchPlaces: SearchPlacesUseCase

    init(searchPlaces: SearchPlacesUseCase) {
        self.searchPlaces = searchPlaces
    }

    /// Marks the current query as submitted, which starts a search.
    func submit() {
        submissionCount += 1
    }

    /// Runs the search for the current query.
    func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .idle
            return
        }
        state = .searching
        do {
            let places = try await searchPlaces(query)
            state = places.isEmpty ? .noMatches : .results(places)
            // One match means there's nothing to choose, so go straight to it.
            if places.count == 1 {
                selection = places.first
            }
        } catch is CancellationError {
            // A newer search replaced this one; it sets the state.
        } catch {
            state = .failed(PlanningFailure(error))
        }
    }

    func select(_ place: Place) {
        selection = place
    }

    /// Call once the view has acted on `selection`.
    func clearSelection() {
        selection = nil
    }
}
