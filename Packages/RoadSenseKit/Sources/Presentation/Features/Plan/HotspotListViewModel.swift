import Application
import Domain
import Foundation
import Observation

/// State and actions for `HotspotListView` (activity diagram 2).
@Observable
final class HotspotListViewModel {
    enum State: Equatable {
        case loading
        /// Ready to drive; the plan's `freshness` says how much to trust its hotspots.
        case ready(TripPlan)
        /// No live or saved hazard data; the driver decides whether to drive anyway.
        case unavailable
    }

    let destination: Place
    let route: Route
    private(set) var state: State = .loading

    @ObservationIgnored private let findHotspots: FindRouteHotspotsUseCase

    init(destination: Place, route: Route, findHotspots: FindRouteHotspotsUseCase) {
        self.destination = destination
        self.route = route
        self.findHotspots = findHotspots
    }

    func load() async {
        state = .loading
        do {
            let plan = try await findHotspots(destination: destination, route: route)
            state = plan.freshness == .unavailable ? .unavailable : .ready(plan)
        } catch {
            // Only cancellation reaches here: the screen went away, so there's nothing to show.
        }
    }

    /// The driver chose to go without hazard data; the trip is still recorded.
    func driveWithoutWarnings() {
        state = .ready(TripPlan(destination: destination, route: route, hotspots: [], freshness: .unavailable))
    }
}
