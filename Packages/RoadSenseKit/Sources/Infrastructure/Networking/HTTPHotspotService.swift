import Application
import Domain
import Foundation

/// Looks up a route's hotspots on the RoadSense server.
public struct HTTPHotspotService: HotspotService {
    private let client: APIClient
    private let deviceIdentity: any DeviceIdentityStore

    public init(client: APIClient, deviceIdentity: any DeviceIdentityStore) {
        self.client = client
        self.deviceIdentity = deviceIdentity
    }

    public func hotspots(along route: Route) async throws -> [RouteHotspot] {
        guard let deviceID = try? await deviceIdentity.deviceID() else { throw HotspotServiceError.unavailable }
        let request = RouteHotspotsRequestDTO(points: route.points.map(PointDTO.init))
        do {
            var (data, status) = try await client.post("v1/routes/hotspots", body: request, deviceID: deviceID)
            // A new install hasn't registered yet: register once and ask again.
            if status == 401 {
                try await client.registerDevice(deviceID)
                (data, status) = try await client.post("v1/routes/hotspots", body: request, deviceID: deviceID)
            }
            switch status {
            case 200:
                return try JSONDecoder().decode(RouteHotspotsResponseDTO.self, from: data).hotspots.map(\.routeHotspot)
            case 400, 401:
                // The server refused (bad route, unknown device); asking again won't help.
                throw HotspotServiceError.rejected
            default:
                throw HotspotServiceError.unavailable
            }
        } catch let error as HotspotServiceError {
            throw error
        } catch {
            // Offline, timed out, or an unreadable reply: worth retrying later.
            throw HotspotServiceError.unavailable
        }
    }
}
