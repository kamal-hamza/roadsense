import SwiftUI

/// The app's root view. Entry point from the composition root into Presentation.
public struct RootView: View {
    private let dependencies: AppDependencies

    public init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    public var body: some View {
        TabView {
            Tab("Record", systemImage: "record.circle") {
                NavigationStack {
                    RecordingView(recordTrip: dependencies.recordTrip)
                }
            }
            Tab("Trips", systemImage: "car") {
                NavigationStack {
                    TripListView(listTrips: dependencies.listTrips, findSensorLog: dependencies.findSensorLog)
                }
            }
        }
    }
}

#Preview {
    RootView(dependencies: .preview)
}
