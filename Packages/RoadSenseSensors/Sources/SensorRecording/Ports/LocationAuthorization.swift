/// Whether the app may use location, reduced to what the app needs to decide.
public enum LocationAuthorization: Hashable, Sendable {
    /// The user hasn't been asked yet.
    case notDetermined
    case denied
    /// Blocked by parental controls or device management; the user can't change it.
    case restricted
    /// When In Use or Always.
    case authorized
}
