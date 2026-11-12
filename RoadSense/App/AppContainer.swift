import Application
import Infrastructure
import Presentation

/// Composition root: the only code that knows concrete Infrastructure types.
///
/// Equivalent to `Program.cs` service registration in ASP.NET Core. To swap an
/// implementation (e.g. in-memory → SwiftData), change it here and nowhere else.
enum AppContainer {
    static func makeLive() -> AppDependencies {
        let tripRepository = InMemoryTripRepository()

        return AppDependencies(
            listTrips: ListTripsUseCase(repository: tripRepository),
        )
    }
}
