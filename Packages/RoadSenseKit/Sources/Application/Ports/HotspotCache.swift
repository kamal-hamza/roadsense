import Domain

/// The on-device copy of hotspots fetched earlier. Implemented in Infrastructure.
public protocol HotspotCache: Sendable {
    /// Saves the hotspots fetched for a route.
    func save(_ area: CachedHotspotArea) async throws

    /// Every saved area, newest first.
    func areas() async throws -> [CachedHotspotArea]
}
