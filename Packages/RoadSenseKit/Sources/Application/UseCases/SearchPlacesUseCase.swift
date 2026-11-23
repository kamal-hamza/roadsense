import Domain
import Foundation
import SensorCore
import SensorRecording

/// Searches for a destination near where the driver is now.
public struct SearchPlacesUseCase: Sendable {
    private let locationServices: any LocationServices
    private let placeSearch: any PlaceSearching

    public init(locationServices: any LocationServices, placeSearch: any PlaceSearching) {
        self.locationServices = locationServices
        self.placeSearch = placeSearch
    }

    /// Matching places, best first. A blank query returns no results without searching.
    /// - Throws: `LocationServicesError` or `MapServiceError`.
    public func callAsFunction(_ query: String) async throws -> [Place] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let here = try await locationServices.currentLocation()
        return try await placeSearch.places(matching: trimmed, near: here.coordinate)
    }
}
