import Domain
import Foundation

/// Finds hotspots for the chosen route, falling back to saved ones when offline (activity diagram 2).
public struct FindRouteHotspotsUseCase: Sendable {
    private let service: any HotspotService
    private let cache: any HotspotCache
    /// Waits before the 2nd and 3rd tries, so three tries in all.
    private let retryDelays: [Duration]
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        service: any HotspotService,
        cache: any HotspotCache,
        retryDelays: [Duration] = [.seconds(1), .seconds(2)],
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init,
    ) {
        self.service = service
        self.cache = cache
        self.retryDelays = retryDelays
        self.sleep = sleep
        self.now = now
    }

    /// A trip plan whose `freshness` says where the hotspots came from; `.unavailable` means there's no data.
    /// - Throws: Only `CancellationError`, if the task is cancelled while waiting to retry.
    public func callAsFunction(destination: Place, route: Route) async throws -> TripPlan {
        if let hotspots = try await fetchWithRetries(route) {
            let area = CachedHotspotArea(route: route, hotspots: hotspots.map(\.hotspot), savedAt: now())
            // The plan is fine without the offline copy, so a failed save shouldn't stop the trip.
            try? await cache.save(area)
            return TripPlan(destination: destination, route: route, hotspots: hotspots, freshness: .live)
        }
        return await cachedPlan(destination: destination, route: route)
            ?? TripPlan(destination: destination, route: route, hotspots: [], freshness: .unavailable)
    }

    /// Hotspots from the backend, or `nil` if every try failed or the request was rejected.
    private func fetchWithRetries(_ route: Route) async throws -> [RouteHotspot]? {
        for attempt in 0 ... retryDelays.count {
            do {
                return try await service.hotspots(along: route)
            } catch HotspotServiceError.rejected {
                // The backend said no; asking again would get the same answer.
                return nil
            } catch {
                guard attempt < retryDelays.count else { return nil }
                // Back off a little longer each time (1 s, then 2 s).
                try await sleep(retryDelays[attempt])
            }
        }
        return nil
    }

    /// Saved hotspots from areas that cover this route, or `nil` if none do.
    private func cachedPlan(destination: Place, route: Route) async -> TripPlan? {
        // A cache we can't read is the same as an empty one: there's nothing to fall back to.
        let areas = await (try? cache.areas()) ?? []
        let covering = areas.filter { $0.covers(route) }
        // Report the oldest copy used, so "may be out of date" is never too optimistic.
        guard let oldest = covering.map(\.savedAt).min() else { return nil }

        // Combine overlapping areas, keeping each hotspot once.
        var seen = Set<Hotspot.ID>()
        let hotspots = covering.flatMap(\.hotspots).filter { seen.insert($0.id).inserted }
        return TripPlan(
            destination: destination,
            route: route,
            hotspots: HotspotLocator().locate(hotspots, along: route),
            freshness: .cached(savedAt: oldest),
        )
    }
}
