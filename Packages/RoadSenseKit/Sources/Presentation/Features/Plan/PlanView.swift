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

    /// A drive in progress, shown full screen over the plan.
    private struct ActiveDrive: Identifiable {
        let id = UUID()
        let plan: TripPlan
    }

    @State private var access: LocationAccessViewModel
    @State private var path: [Step] = []
    @State private var activeDrive: ActiveDrive?
    /// Bumped when a drive's summary is closed, which kicks off an upload.
    @State private var finishedDrives = 0
    @Environment(\.scenePhase) private var scenePhase

    private let searchPlaces: SearchPlacesUseCase
    private let planRoute: PlanRouteUseCase
    private let findHotspots: FindRouteHotspotsUseCase
    private let driveTrip: DriveTripUseCase
    private let submitFeedback: SubmitTripFeedbackUseCase
    private let uploadPendingEvents: UploadPendingEventsUseCase

    init(
        checkAccess: CheckLocationAccessUseCase,
        searchPlaces: SearchPlacesUseCase,
        planRoute: PlanRouteUseCase,
        findHotspots: FindRouteHotspotsUseCase,
        driveTrip: DriveTripUseCase,
        submitFeedback: SubmitTripFeedbackUseCase,
        uploadPendingEvents: UploadPendingEventsUseCase,
    ) {
        _access = State(initialValue: LocationAccessViewModel(checkAccess: checkAccess))
        self.searchPlaces = searchPlaces
        self.planRoute = planRoute
        self.findHotspots = findHotspots
        self.driveTrip = driveTrip
        self.submitFeedback = submitFeedback
        self.uploadPendingEvents = uploadPendingEvents
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
        // Full screen hides the tabs and everything else that isn't about the road.
        .fullScreen(item: $activeDrive) { drive in
            DriveView(plan: drive.plan, driveTrip: driveTrip, submitFeedback: submitFeedback) {
                activeDrive = nil
                // Back to the search screen, ready for the next trip.
                path.removeAll()
                finishedDrives += 1
            }
        }
        // Send the finished drive (with any feedback). Failures stay queued and retry at the next launch.
        .task(id: finishedDrives) {
            guard finishedDrives > 0 else { return }
            await BackgroundWork.run("Uploading events") { try await uploadPendingEvents() }
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
            HotspotListView(destination: place, route: route, findHotspots: findHotspots) { plan in
                activeDrive = ActiveDrive(plan: plan)
            }
        }
    }
}

#Preview("Plan") {
    PlanView(
        checkAccess: AppDependencies.preview.checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
        findHotspots: AppDependencies.preview.findRouteHotspots,
        driveTrip: AppDependencies.preview.driveTrip,
        submitFeedback: AppDependencies.preview.submitTripFeedback,
        uploadPendingEvents: AppDependencies.preview.uploadPendingEvents,
    )
}

#Preview("Permission needed") {
    PlanView(
        checkAccess: AppDependencies.preview(authorization: .notDetermined).checkLocationAccess,
        searchPlaces: AppDependencies.preview.searchPlaces,
        planRoute: AppDependencies.preview.planRoute,
        findHotspots: AppDependencies.preview.findRouteHotspots,
        driveTrip: AppDependencies.preview.driveTrip,
        submitFeedback: AppDependencies.preview.submitTripFeedback,
        uploadPendingEvents: AppDependencies.preview.uploadPendingEvents,
    )
}
