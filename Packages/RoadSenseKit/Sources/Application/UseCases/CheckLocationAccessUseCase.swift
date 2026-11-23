import SensorRecording

/// Checks, and when needed asks for, permission to use location (activity diagram 1).
public struct CheckLocationAccessUseCase: Sendable {
    private let locationServices: any LocationServices

    public init(locationServices: any LocationServices) {
        self.locationServices = locationServices
    }

    /// The current permission, without prompting.
    public func callAsFunction() async -> LocationAuthorization {
        await locationServices.authorization()
    }

    /// Shows the system prompt if the user hasn't been asked yet, and returns the answer.
    public func request() async -> LocationAuthorization {
        await locationServices.requestAuthorization()
    }
}
