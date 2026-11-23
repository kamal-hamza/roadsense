/// Violations of `Trip` invariants.
public enum TripError: Error, Equatable, Sendable {
    case emptyName
    case negativeDistance
    case endsBeforeStart
}
