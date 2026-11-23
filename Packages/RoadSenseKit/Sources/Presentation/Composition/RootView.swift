import Application
import SwiftUI

/// The app's root view. Entry point from the composition root into Presentation.
public struct RootView: View {
    private enum TabID: Hashable {
        case drive, trips, settings
    }

    private let dependencies: AppDependencies
    @State private var selectedTab = Self.initialTab

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Drive", systemImage: "car.fill", value: TabID.drive) {
                PlanView(
                    checkAccess: dependencies.checkLocationAccess,
                    searchPlaces: dependencies.searchPlaces,
                    planRoute: dependencies.planRoute,
                    findHotspots: dependencies.findRouteHotspots,
                    driveTrip: dependencies.driveTrip,
                    submitFeedback: dependencies.submitTripFeedback,
                    uploadPendingEvents: dependencies.uploadPendingEvents,
                )
            }
            Tab("Trips", systemImage: "list.bullet", value: TabID.trips) {
                NavigationStack {
                    TripListView(listTrips: dependencies.listTrips, findSensorLog: dependencies.findSensorLog)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    SettingsView(recordTrip: dependencies.recordTrip, managePreferences: dependencies.managePreferences)
                }
            }
        }
        .task {
            // A drive cut off last time (app closed, battery died) is closed as incomplete, with no summary.
            await BackgroundWork.run("Recovering an incomplete trip") { try await dependencies.recoverIncompleteTrip() }
            // Then send whatever is waiting. Failures stay queued for next time, so they're logged, not shown.
            await BackgroundWork.run("Uploading events") { try await dependencies.uploadPendingEvents() }
        }
    }

    /// The Drive tab, unless the `-autoStartRecording` dev hook asks for the recording screen under Settings.
    private static var initialTab: TabID {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-autoStartRecording") {
                return .settings
            }
        #endif
        return .drive
    }
}

#Preview {
    RootView(dependencies: .preview)
}
