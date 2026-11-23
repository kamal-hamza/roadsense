import Application
import Domain
import Foundation
import MapKit
import OSLog
import SensorCore

/// Driving directions with MapKit's `MKDirections`, including alternative routes.
public struct MapKitDirections: DirectionsProviding {
    private static let logger = Logger(subsystem: "com.hkamal.RoadSense", category: "Directions")

    public init() {}

    public func routes(from origin: Coordinate, to destination: Place) async throws -> [Route] {
        let request = MKDirections.Request()
        request.source = .at(origin)
        request.destination = .at(destination.coordinate)
        request.transportType = .automobile
        request.requestsAlternateRoutes = true

        let response: MKDirections.Response
        do {
            response = try await MKDirections(request: request).calculate()
        } catch {
            guard let mapped = MapServiceError(mapKitError: error) else { return [] }
            throw mapped
        }

        return response.routes.compactMap { route in
            do {
                return try Route(
                    polyline: route.polyline,
                    name: route.name,
                    expectedTravelTime: route.expectedTravelTime,
                )
            } catch {
                // A degenerate polyline can't be driven or warned along, so leave that option out.
                Self.logger.error("Skipped a route with an unusable polyline: \(String(describing: error))")
                return nil
            }
        }
    }
}
