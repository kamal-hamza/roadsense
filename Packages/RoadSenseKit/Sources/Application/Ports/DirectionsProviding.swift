import Domain
import SensorCore

/// Driving directions. Implemented in Infrastructure.
public protocol DirectionsProviding: Sendable {
    /// Driving routes from `origin` to `destination`, best first. Empty when there's no driving route.
    /// - Throws: `MapServiceError`.
    func routes(from origin: Coordinate, to destination: Place) async throws -> [Route]
}
