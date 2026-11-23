import Domain

/// This install's anonymous device id, created on first use and kept securely. Implemented in Infrastructure.
public protocol DeviceIdentityStore: Sendable {
    func deviceID() async throws -> DeviceID
}
