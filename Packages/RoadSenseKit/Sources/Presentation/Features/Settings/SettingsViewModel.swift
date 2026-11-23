import Application
import Foundation
import Observation

/// State and actions for `SettingsView`.
@Observable
final class SettingsViewModel {
    private(set) var preferences = AppPreferences()
    private(set) var isLoaded = false

    @ObservationIgnored private let managePreferences: ManagePreferencesUseCase

    init(managePreferences: ManagePreferencesUseCase) {
        self.managePreferences = managePreferences
    }

    func load() async {
        preferences = await managePreferences()
        isLoaded = true
    }

    func setWarningsEnabled(_ isEnabled: Bool) async {
        preferences.warningsEnabled = isEnabled
        await managePreferences.save(preferences)
    }

    func setDataSharingEnabled(_ isEnabled: Bool) async {
        preferences.dataSharingEnabled = isEnabled
        await managePreferences.save(preferences)
    }
}
