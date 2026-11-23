/// Why a map-service request failed. Infrastructure maps framework errors to these.
public enum MapServiceError: Error, Equatable, Sendable {
    /// Offline, timed out, or the service had a problem; worth trying again.
    case unavailable
    /// Too many requests in a short time; try again in a minute.
    case throttled
}
