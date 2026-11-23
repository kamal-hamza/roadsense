import Application
import Domain
import SwiftUI

/// Lists recorded trips.
struct TripListView: View {
    @State private var viewModel: TripListViewModel
    private let findSensorLog: FindSensorLogUseCase

    init(listTrips: ListTripsUseCase, findSensorLog: FindSensorLogUseCase) {
        _viewModel = State(initialValue: TripListViewModel(listTrips: listTrips))
        self.findSensorLog = findSensorLog
    }

    var body: some View {
        content
            .navigationTitle("Trips")
            // Tapping a NavigationLink(value: trip) below opens this screen.
            .navigationDestination(for: Trip.self) { trip in
                TripDetailView(trip: trip, findSensorLog: findSensorLog)
            }
            // Re-runs each time the tab appears, so newly recorded trips show up.
            .task { await viewModel.load() }
            .refreshable { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case let .loaded(trips) where trips.isEmpty:
            ContentUnavailableView(
                "No Trips",
                systemImage: "car",
                description: Text("Trips you record will appear here."),
            )
        case let .loaded(trips):
            List(trips) { trip in
                NavigationLink(value: trip) {
                    TripRow(trip: trip)
                }
            }
        case let .failed(message):
            ContentUnavailableView(
                "Couldn't Load Trips",
                systemImage: "exclamationmark.triangle",
                description: Text(message),
            )
        }
    }
}

#Preview("Trips") {
    NavigationStack {
        TripListView(listTrips: AppDependencies.preview.listTrips, findSensorLog: AppDependencies.preview.findSensorLog)
    }
}

#Preview("Empty") {
    NavigationStack {
        TripListView(
            listTrips: AppDependencies.preview(trips: []).listTrips,
            findSensorLog: AppDependencies.preview.findSensorLog,
        )
    }
}
