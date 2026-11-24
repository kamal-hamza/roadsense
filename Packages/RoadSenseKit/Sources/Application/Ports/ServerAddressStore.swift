import Foundation

/// A developer-chosen server address that replaces the built-in one, e.g. a Tailscale address for testing
/// on a phone. Only debug builds use it. Implemented in Infrastructure.
public protocol ServerAddressStore: Sendable {
    func load() async -> URL?
    /// Saves `address`, or clears it with `nil` so the built-in address is used again.
    func save(_ address: URL?) async
}
