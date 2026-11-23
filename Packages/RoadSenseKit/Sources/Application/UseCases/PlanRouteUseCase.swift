import Domain
import SensorCore
import SensorRecording

/// Gets driving routes from where the driver is now to the chosen place.
public struct PlanRouteUseCase: Sendable {
    private let locationServices: any LocationServices
    private let directions: any DirectionsProviding

    public init(locationServices: any LocationServices, directions: any DirectionsProviding) {
        self.locationServices = locationServices
        self.directions = directions
    }

    /// Route options, best first. Empty means there's no driving route.
    /// - Throws: `LocationServicesError` or `MapServiceError`.
    public func callAsFunction(to destination: Place) async throws -> [Route] {
        let here = try await locationServices.currentLocation()
        return try await directions.routes(from: here.coordinate, to: destination)
    }
}
