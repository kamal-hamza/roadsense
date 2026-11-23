import Domain
import SensorCore

/// Finds places by name or address. Implemented in Infrastructure.
public protocol PlaceSearching: Sendable {
    /// Places matching `query`, best match first, preferring ones near `center`.
    /// - Throws: `MapServiceError`.
    func places(matching query: String, near center: Coordinate) async throws -> [Place]
}
