import Application
import Domain
import SwiftUI

/// Lets the driver search for where they're going.
struct DestinationSearchView: View {
    @State private var viewModel: DestinationSearchViewModel
    private let onSelect: (Place) -> Void

    init(searchPlaces: SearchPlacesUseCase, onSelect: @escaping (Place) -> Void) {
        _viewModel = State(initialValue: DestinationSearchViewModel(searchPlaces: searchPlaces))
        self.onSelect = onSelect
    }

    var body: some View {
        @Bindable var viewModel = viewModel
        content
            .navigationTitle("Plan a Drive")
            .searchable(text: $viewModel.query, prompt: "Place or address")
            // Search on submit rather than on every keystroke: less typing noise and fewer map requests.
            .onSubmit(of: .search) { viewModel.submit() }
            // Restarting on each submit cancels a search that's still running.
            .task(id: viewModel.submissionCount) {
                guard viewModel.submissionCount > 0 else { return }
                await viewModel.search()
            }
            .onChange(of: viewModel.selection) { _, place in
                guard let place else { return }
                viewModel.clearSelection()
                onSelect(place)
            }
        #if DEBUG
            // Dev hook for automated screenshots: launch with `-searchDestination "Space Needle"`.
            .task {
                if let query = UserDefaults.standard.string(forKey: "searchDestination"), viewModel.query.isEmpty {
                    viewModel.query = query
                    viewModel.submit()
                }
            }
        #endif
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle:
            ContentUnavailableView(
                "Where To?",
                systemImage: "magnifyingglass",
                description: Text("Search for a place or address to see hazards on the way."),
            )
        case .searching:
            ProgressView()
        case .noMatches:
            ContentUnavailableView(
                "No Matches",
                systemImage: "mappin.slash",
                description: Text("Check the spelling, or try a nearby street or landmark."),
            )
        case let .failed(failure):
            PlanningFailureView(failure: failure)
        case let .results(places):
            List(places, id: \.self) { place in
                Button { viewModel.select(place) } label: {
                    PlaceRow(place: place)
                }
                .tint(.primary)
            }
        }
    }
}

#Preview("Search") {
    NavigationStack {
        DestinationSearchView(searchPlaces: AppDependencies.preview.searchPlaces) { _ in }
    }
}
