import Application
import Foundation

/// Keeps the server address override in `UserDefaults`. A `-apiBaseURL <url>` launch argument sets the same
/// key, since launch arguments become `UserDefaults` values for that run.
public struct UserDefaultsServerAddressStore: ServerAddressStore {
    static let key = "apiBaseURL"
    /// UserDefaults isn't Sendable, so keep the suite's name and look it up on each use.
    private let suiteName: String?

    /// - Parameter suiteName: Tests pass their own suite; `nil` is the standard one.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    /// The override right now, read synchronously for the composition root at launch.
    public var current: URL? {
        defaults.string(forKey: Self.key).flatMap(URL.init(string:))
    }

    public func load() async -> URL? {
        current
    }

    public func save(_ address: URL?) async {
        if let address {
            defaults.set(address.absoluteString, forKey: Self.key)
        } else {
            defaults.removeObject(forKey: Self.key)
        }
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
