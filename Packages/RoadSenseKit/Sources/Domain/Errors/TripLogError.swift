/// Violations of `TripLog` rules.
public enum TripLogError: Error, Equatable, Sendable {
    case alreadyFinished
    case endsBeforeStart
}
