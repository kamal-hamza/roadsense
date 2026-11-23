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
                )
            }
            Tab("Trips", systemImage: "list.bullet", value: TabID.trips) {
                NavigationStack {
                    TripListView(listTrips: dependencies.listTrips, findSensorLog: dependencies.findSensorLog)
                }
            }
            Tab("Settings", systemImage: "gearshape", value: TabID.settings) {
                NavigationStack {
                    SettingsView(recordTrip: dependencies.recordTrip)
                }
            }
        }
        // A drive cut off last time (app closed, battery died) is closed as incomplete; there's nothing to show.
        .task { _ = try? await dependencies.recoverIncompleteTrip() }
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
