/// Why the backend couldn't return hotspots. Infrastructure maps HTTP and network errors to these.
public enum HotspotServiceError: Error, Equatable, Sendable {
    /// The backend refused the request (unknown device, bad route data). Retrying won't help.
    case rejected
    /// Offline, timed out, or a server error. Worth retrying.
    case unavailable
}
