import Application
import Domain
import SensorRecording
import SwiftUI

/// The Drive tab: get location permission, pick a destination, pick a route, then see its hazards.
struct PlanView: View {
    /// The screens pushed after the search screen.
    private enum Step: Hashable {
        case routes(to: Place)
        case hazards(to: Place, along: Route)
    }

    @State private var access: LocationAccessViewModel
    @State private var path: [Step] = []
    @Environment(\.scenePhase) private var scenePhase

    private let searchPlaces: SearchPlacesUseCase
    private let planRoute: PlanRouteUseCase
    private let findHotspots: FindRouteHotspotsUseCase

    init(
        checkAccess: CheckLocationAccessUseCase,
        searchPlaces: SearchPlacesUseCase,
        planRoute: PlanRouteUseCase,
        findHotspots: FindRouteHotspotsUseCase,
    ) {
        _access = State(initialValue: LocationAccessViewModel(checkAccess: checkAccess))
        self.searchPlaces = searchPlaces
        self.planRoute = planRoute
        self.findHotspots = findHotspots
    }

    var body: some View {
        Group {
            if access.state == .granted {
                NavigationStack(path: $path) {
                    DestinationSearchView(searchPlaces: searchPlaces) { path.append(.routes(to: $0)) }
                        .navigationDestination(for: Step.self, destination: screen(for:))
                }
            } else {
                LocationAccessView(viewModel: access)
            }
        }
        // Re-check on launch and whenever the app comes back, e.g. from Settings.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await access.check()
        }
    }

    @ViewBuilder
    private func screen(for step: Step) -> some View {
        switch step {
        case let .routes(place):
            RouteChoiceView(destination: place, planRoute: planRoute) { route in
                path.append(.hazards(to: place, along: route))
            }
        case let .hazards(place, route):
            HotspotListView(destination: place, route: route, findHotspots: findHotspots)
        }
    }
}

#Preview("Plan") {
    PlanView(
        checkAccess: AppDependencies.preview.checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
        findHotspots: AppDependencies.preview.findRouteHotspots,
    )
}

#Preview("Permission needed") {
    PlanView(
        checkAccess: AppDependencies.preview(authorization: .notDetermined).checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
        findHotspots: AppDependencies.preview.findRouteHotspots,
    )
}
