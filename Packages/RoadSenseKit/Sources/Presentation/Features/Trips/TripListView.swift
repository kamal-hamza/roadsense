import Application
import Domain
import SwiftUI

/// Lists recorded trips.
struct TripListView: View {
    @State private var viewModel: TripListViewModel

    init(listTrips: ListTripsUseCase) {
        _viewModel = State(initialValue: TripListViewModel(listTrips: listTrips))
    }

    var body: some View {
        content
            .navigationTitle("Trips")
            .task { await viewModel.load() }
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
                TripRow(trip: trip)
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
        TripListView(listTrips: AppDependencies.preview.listTrips)
    }
}

#Preview("Empty") {
    NavigationStack {
        TripListView(listTrips: AppDependencies.preview(trips: []).listTrips)
    }
}
