/// Why the current location couldn't be read.
public enum LocationServicesError: Error, Equatable, Sendable {
    case notAuthorized
    /// No fix in time (no signal, location services off).
    case unavailable
}
