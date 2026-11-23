import Application
import Domain
import MapKit
import SwiftUI

/// Shows driving routes to the chosen place and lets the driver pick one.
struct RouteChoiceView: View {
    @State private var viewModel: RouteChoiceViewModel
    private let onChoose: (Route) -> Void

    init(destination: Place, planRoute: PlanRouteUseCase, onChoose: @escaping (Route) -> Void) {
        _viewModel = State(initialValue: RouteChoiceViewModel(destination: destination, planRoute: planRoute))
        self.onChoose = onChoose
    }

    var body: some View {
        content
            .navigationTitle(viewModel.destination.name)
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .task {
                await viewModel.load()
                #if DEBUG
                    // Dev hook for automated screenshots: `-autoCheckHazards` continues with the best route.
                    if ProcessInfo.processInfo.arguments.contains("-autoCheckHazards"),
                       let route = viewModel.selectedRoute
                    {
                        onChoose(route)
                    }
                #endif
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
        case .noRoute:
            ContentUnavailableView(
                "No Driving Route Found",
                systemImage: "car.side.rear.and.collision.and.car.side.front.slash",
                description: Text("There's no road route to this place. Try a different destination."),
            )
        case let .failed(failure):
            PlanningFailureView(failure: failure)
        case let .loaded(routes):
            VStack(spacing: 0) {
                RouteMap(routes: routes, selectedIndex: viewModel.selectedIndex, destination: viewModel.destination)
                    .frame(minHeight: 240)
                List(routes.indices, id: \.self) { index in
                    Button { viewModel.select(routeAt: index) } label: {
                        RouteOptionRow(route: routes[index], isSelected: index == viewModel.selectedIndex)
                    }
                    .tint(.primary)
                }
                .listStyle(.plain)
            }
            .safeAreaInset(edge: .bottom) {
                if let route = viewModel.selectedRoute {
                    Button { onChoose(route) } label: {
                        Text("Check for Hazards")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding()
                }
            }
        }
    }
}

/// The route options on a map, the chosen one drawn on top and thicker.
private struct RouteMap: View {
    let routes: [Route]
    let selectedIndex: Int?
    let destination: Place

    var body: some View {
        Map(initialPosition: .automatic) {
            // Unselected routes first so the chosen one draws over them.
            ForEach(routes.indices.filter { $0 != selectedIndex }, id: \.self) { index in
                MapPolyline(coordinates: routes[index].points.map(CLLocationCoordinate2D.init))
                    .stroke(.gray.opacity(0.7), lineWidth: 4)
            }
            if let selectedIndex {
                MapPolyline(coordinates: routes[selectedIndex].points.map(CLLocationCoordinate2D.init))
                    .stroke(.tint, lineWidth: 7)
            }
            Marker(destination.name, coordinate: CLLocationCoordinate2D(destination.coordinate))
        }
        // The list below carries the same information for VoiceOver.
        .accessibilityHidden(true)
    }
}

#Preview("Routes") {
    NavigationStack {
        RouteChoiceView(destination: .previewDestination, planRoute: AppDependencies.preview.planRoute) { _ in }
    }
}

#Preview("No route") {
    NavigationStack {
        RouteChoiceView(
            destination: .previewDestination,
            planRoute: AppDependencies.preview(routes: []).planRoute,
        ) { _ in
        }
    }
}
