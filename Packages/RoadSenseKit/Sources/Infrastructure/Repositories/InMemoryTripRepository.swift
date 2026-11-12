import Application
import Domain

/// Keeps trips in memory for the lifetime of the process.
///
/// Placeholder until a persistent store (e.g. SwiftData) is added. Swap it in the
/// composition root (`RoadSense/App/AppContainer.swift`) without touching other layers.
public actor InMemoryTripRepository: TripRepository {
    private var tripsByID: [Trip.ID: Trip]

    public init(trips: [Trip] = []) {
        tripsByID = Dictionary(uniqueKeysWithValues: trips.map { ($0.id, $0) })
    }

    public func allTrips() -> [Trip] {
        Array(tripsByID.values)
    }

    public func save(_ trip: Trip) {
        tripsByID[trip.id] = trip
    }
}
