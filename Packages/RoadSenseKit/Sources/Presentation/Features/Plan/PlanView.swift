import Application
import Domain
import SensorRecording
import SwiftUI

/// The Drive tab: get location permission, pick a destination, then pick a route.
struct PlanView: View {
    @State private var access: LocationAccessViewModel
    @State private var path: [Place] = []
    @Environment(\.scenePhase) private var scenePhase

    private let searchPlaces: SearchPlacesUseCase
    private let planRoute: PlanRouteUseCase

    init(checkAccess: CheckLocationAccessUseCase, searchPlaces: SearchPlacesUseCase, planRoute: PlanRouteUseCase) {
        _access = State(initialValue: LocationAccessViewModel(checkAccess: checkAccess))
        self.searchPlaces = searchPlaces
        self.planRoute = planRoute
    }

    var body: some View {
        Group {
            if access.state == .granted {
                NavigationStack(path: $path) {
                    DestinationSearchView(searchPlaces: searchPlaces) { path.append($0) }
                        .navigationDestination(for: Place.self) { place in
                            RouteChoiceView(destination: place, planRoute: planRoute)
                        }
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
}

#Preview("Plan") {
    PlanView(
        checkAccess: AppDependencies.preview.checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
    )
}

#Preview("Permission needed") {
    PlanView(
        checkAccess: AppDependencies.preview(authorization: .notDetermined).checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
    )
}
