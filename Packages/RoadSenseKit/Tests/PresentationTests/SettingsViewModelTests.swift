import Application
@testable import Presentation
import Testing

struct SettingsViewModelTests {
    @Test func `loads the saved settings and saves changes`() async {
        let store = StoredPreferences(AppPreferences(warningsEnabled: true, dataSharingEnabled: false))
        let viewModel = SettingsViewModel(managePreferences: ManagePreferencesUseCase(preferences: store))

        await viewModel.load()
        let loaded = viewModel.preferences
        await viewModel.setWarningsEnabled(false)
        await viewModel.setDataSharingEnabled(true)

        #expect(loaded == AppPreferences(warningsEnabled: true, dataSharingEnabled: false))
        #expect(viewModel.isLoaded)
        #expect(await store.load() == AppPreferences(warningsEnabled: false, dataSharingEnabled: true))
    }
}

private actor StoredPreferences: UserPreferences {
    private var stored: AppPreferences

    init(_ stored: AppPreferences) {
        self.stored = stored
    }

    func load() async -> AppPreferences {
        stored
    }

    func save(_ preferences: AppPreferences) async {
        stored = preferences
    }
}
