import Application
import Foundation
import Observation

/// State and actions for `SettingsView`.
@Observable
final class SettingsViewModel {
    enum ServerAddressStatus: Equatable {
        case unchanged
        /// Saved; it's used from the next launch.
        case saved
        case invalid
    }

    private(set) var preferences = AppPreferences()
    private(set) var isLoaded = false
    /// What's typed in the server address field (debug builds).
    var serverAddress = ""
    private(set) var serverAddressStatus: ServerAddressStatus = .unchanged

    @ObservationIgnored private let managePreferences: ManagePreferencesUseCase
    @ObservationIgnored private let manageServerAddress: ManageServerAddressUseCase

    init(managePreferences: ManagePreferencesUseCase, manageServerAddress: ManageServerAddressUseCase) {
        self.managePreferences = managePreferences
        self.manageServerAddress = manageServerAddress
    }

    func load() async {
        preferences = await managePreferences()
        serverAddress = await manageServerAddress()?.absoluteString ?? ""
        isLoaded = true
    }

    func saveServerAddress() async {
        do {
            try await manageServerAddress.save(serverAddress)
            serverAddressStatus = .saved
        } catch {
            serverAddressStatus = .invalid
        }
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
