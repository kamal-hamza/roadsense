/// Reads and changes the driver's settings.
public struct ManagePreferencesUseCase: Sendable {
    private let preferences: any UserPreferences

    public init(preferences: any UserPreferences) {
        self.preferences = preferences
    }

    public func callAsFunction() async -> AppPreferences {
        await preferences.load()
    }

    public func save(_ newPreferences: AppPreferences) async {
        await preferences.save(newPreferences)
    }
}
