/// Why a drive ended.
public enum TripEndReason: String, Hashable, Sendable, Codable {
    /// Close to the destination and stopped.
    case arrived
    /// The driver tapped End Trip.
    case endedByDriver
    /// The app was closed or the battery died; closed on the next launch.
    case incomplete
}
