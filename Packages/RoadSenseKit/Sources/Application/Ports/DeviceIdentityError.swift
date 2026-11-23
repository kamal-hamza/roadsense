/// Why the device id couldn't be read or created.
public enum DeviceIdentityError: Error, Equatable, Sendable {
    /// Secure storage isn't available (e.g. before the phone's first unlock after a restart).
    case storageUnavailable
}
