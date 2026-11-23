import Application
import Domain
import Foundation
import Observation

/// State and actions for `RouteChoiceView` (activity diagram 1, route choice).
@Observable
final class RouteChoiceViewModel {
    enum State: Equatable {
        case loading
        case loaded([Route])
        case noRoute
        case failed(PlanningFailure)
    }

    let destination: Place
    private(set) var state: State = .loading
    /// Index into the loaded routes. The first (best) route is picked by default.
    private(set) var selectedIndex: Int?

    @ObservationIgnored private let planRoute: PlanRouteUseCase

    init(destination: Place, planRoute: PlanRouteUseCase) {
        self.destination = destination
        self.planRoute = planRoute
    }

    var routes: [Route] {
        if case let .loaded(routes) = state {
            routes
        } else {
            []
        }
    }

    var selectedRoute: Route? {
        selectedIndex.flatMap { routes.indices.contains($0) ? routes[$0] : nil }
    }

    /// Fetches route options from the driver's current location.
    func load() async {
        state = .loading
        selectedIndex = nil
        do {
            let routes = try await planRoute(to: destination)
            state = routes.isEmpty ? .noRoute : .loaded(routes)
            selectedIndex = routes.isEmpty ? nil : 0
        } catch is CancellationError {
            // The screen went away; nothing to show.
        } catch {
            state = .failed(PlanningFailure(error))
        }
    }

    func select(routeAt index: Int) {
        guard routes.indices.contains(index) else { return }
        selectedIndex = index
    }
}
