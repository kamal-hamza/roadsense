import Domain

/// Stores and retrieves trips.
///
/// A port: Application owns the protocol, Infrastructure provides the implementation.
public protocol TripRepository: Sendable {
    /// Returns every stored trip, in no particular order.
    func allTrips() async throws -> [Trip]

    /// Inserts `trip`, or replaces the stored trip with the same `id`.
    func save(_ trip: Trip) async throws
}
