import SensorCore

/// Location permission and one-off position lookups, for planning a trip before recording starts.
public protocol LocationServices: Sendable {
    /// The current authorization, without prompting.
    func authorization() async -> LocationAuthorization

    /// Shows the When In Use prompt if the user hasn't been asked, and returns the result.
    func requestAuthorization() async -> LocationAuthorization

    /// One recent GPS fix.
    /// - Throws: `LocationServicesError`.
    func currentLocation() async throws -> LocationSample
}
