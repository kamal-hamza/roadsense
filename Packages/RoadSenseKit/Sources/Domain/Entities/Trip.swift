import Foundation

/// A single recorded drive.
///
/// Example entity for the layered architecture. Replace it with real domain types.
public struct Trip: Identifiable, Hashable, Sendable {
    public let id: UUID
    public private(set) var name: String
    public let startedAt: Date
    public private(set) var distance: Measurement<UnitLength>

    /// Creates a trip, enforcing domain invariants.
    ///
    /// - Throws: `TripError.emptyName` if `name` is blank,
    ///   `TripError.negativeDistance` if `distance` is below zero.
    public init(
        id: UUID = UUID(),
        name: String,
        startedAt: Date,
        distance: Measurement<UnitLength>,
    ) throws(TripError) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw .emptyName }
        guard distance.value >= 0 else { throw .negativeDistance }

        self.id = id
        self.name = trimmedName
        self.startedAt = startedAt
        self.distance = distance
    }
}
