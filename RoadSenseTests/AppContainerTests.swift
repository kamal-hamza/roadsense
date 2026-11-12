import Application
import Presentation
@testable import RoadSense
import Testing

/// Smoke tests for the composition root. Layer logic is tested in Packages/RoadSenseKit/Tests.
@MainActor
struct AppContainerTests {
    @Test func `live dependencies resolve`() async throws {
        let dependencies = AppContainer.makeLive()
        _ = try await dependencies.listTrips()
    }
}
