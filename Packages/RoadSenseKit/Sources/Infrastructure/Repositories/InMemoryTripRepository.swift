import Application
import Domain

/// Keeps trips in memory for the lifetime of the process (tests and placeholders).
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
