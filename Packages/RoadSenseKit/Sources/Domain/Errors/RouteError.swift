/// Violations of `Route` invariants.
public enum RouteError: Error, Equatable, Sendable {
    /// A route needs at least two distinct points.
    case tooFewPoints
    case negativeTravelTime
}
