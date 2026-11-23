import Application
import Domain
import SwiftUI

/// The short list of hotspots on the chosen route, in the order the driver reaches them.
struct HotspotListView: View {
    @State private var viewModel: HotspotListViewModel
    @Environment(\.dismiss) private var dismiss

    init(destination: Place, route: Route, findHotspots: FindRouteHotspotsUseCase) {
        _viewModel = State(initialValue: HotspotListViewModel(
            destination: destination,
            route: route,
            findHotspots: findHotspots,
        ))
    }

    var body: some View {
        content
            .navigationTitle("Hazards")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task { await viewModel.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView("Checking for hazards…")
        case .unavailable:
            ContentUnavailableView {
                Label("Hazard Data Unavailable", systemImage: "wifi.slash")
            } description: {
                Text(
                    "Couldn't get hazard data for this route. You can still drive, but you won't get warnings.",
                )
            } actions: {
                Button("Drive Without Warnings") { viewModel.driveWithoutWarnings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("Cancel", role: .cancel) { dismiss() }
                    .controlSize(.large)
            }
        case let .ready(plan):
            TripPlanList(plan: plan)
        }
    }
}

/// The hotspot list for a ready plan, with a note when the data is old or missing.
private struct TripPlanList: View {
    let plan: TripPlan

    var body: some View {
        List {
            switch plan.freshness {
            case .live:
                EmptyView()
            case let .cached(savedAt):
                Section {
                    Label {
                        Text(
                            "Hazards may be out of date. Saved \(savedAt, format: .relative(presentation: .named)).",
                        )
                    } icon: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
            case .unavailable:
                Section {
                    Label("No warnings on this drive. It will still be recorded.", systemImage: "speaker.slash")
                }
            }

            if plan.freshness != .unavailable {
                Section("On Your Route") {
                    if plan.hotspots.isEmpty {
                        Label("No known hotspots on this route.", systemImage: "checkmark.circle")
                    } else {
                        ForEach(plan.hotspots) { HotspotRow(routeHotspot: $0) }
                    }
                }
            }
        }
    }
}

#Preview("Hotspots") {
    NavigationStack {
        HotspotListView(
            destination: .previewDestination,
            route: Route.previewSamples[0],
            findHotspots: AppDependencies.preview.findRouteHotspots,
        )
    }
}

#Preview("Offline, nothing saved") {
    NavigationStack {
        HotspotListView(
            destination: .previewDestination,
            route: Route.previewSamples[0],
            findHotspots: AppDependencies.preview(hotspotsAvailable: false).findRouteHotspots,
        )
    }
}
