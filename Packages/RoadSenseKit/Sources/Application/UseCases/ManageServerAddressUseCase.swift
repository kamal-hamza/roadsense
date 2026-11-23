import Foundation

/// Why a typed server address can't be used.
public enum ServerAddressError: Error, Equatable, Sendable {
    /// It needs to look like `https://your-mac.your-tailnet.ts.net`.
    case invalid
}

/// Reads and changes the developer's server address override (debug builds).
public struct ManageServerAddressUseCase: Sendable {
    private let store: any ServerAddressStore

    public init(store: any ServerAddressStore) {
        self.store = store
    }

    public func callAsFunction() async -> URL? {
        await store.load()
    }

    /// Saves the typed address; an empty one clears the override.
    /// - Throws: `ServerAddressError.invalid` unless it's an http(s) URL with a host.
    public func save(_ text: String) async throws(ServerAddressError) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await store.save(nil)
            return
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host(), !host.isEmpty
        else { throw .invalid }
        await store.save(url)
    }
}
