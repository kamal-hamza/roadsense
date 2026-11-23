import Application
import Foundation

/// Stores the driver's settings in `UserDefaults` as one JSON value.
public struct UserDefaultsPreferences: UserPreferences {
    private static let key = "appPreferences"
    /// UserDefaults isn't Sendable, so keep the suite's name and look it up on each use (it's cached by the system).
    private let suiteName: String?

    /// - Parameter suiteName: Tests pass their own suite so they don't touch the app's settings; `nil` is the standard
    /// one.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func load() async -> AppPreferences {
        // Nothing saved yet (or unreadable after an app update) means the defaults: warnings and sharing on.
        guard let data = defaults.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(AppPreferences.self, from: data)
        else { return AppPreferences() }
        return preferences
    }

    public func save(_ preferences: AppPreferences) async {
        // Encoding two booleans can't fail in practice; there's nothing useful to do if it somehow does.
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
