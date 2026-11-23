/// The driver's settings, kept on the phone. Implemented in Infrastructure.
public protocol UserPreferences: Sendable {
    func load() async -> AppPreferences
    func save(_ preferences: AppPreferences) async
}
