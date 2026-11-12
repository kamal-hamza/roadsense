import Application

/// The use cases the Presentation layer needs, supplied by the composition root.
///
/// Presentation never constructs Infrastructure types. The app target builds this
/// value (see `RoadSense/App/AppContainer.swift`) and passes it to `RootView`.
public struct AppDependencies: Sendable {
    public let listTrips: ListTripsUseCase

    public init(listTrips: ListTripsUseCase) {
        self.listTrips = listTrips
    }
}
