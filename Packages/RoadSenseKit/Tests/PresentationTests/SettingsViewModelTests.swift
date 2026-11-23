import Application
import Foundation
@testable import Presentation
import Testing

struct SettingsViewModelTests {
    private func makeViewModel(
        preferences: StoredPreferences = StoredPreferences(AppPreferences()),
        address: StoredAddress = StoredAddress(),
    ) -> SettingsViewModel {
        SettingsViewModel(
            managePreferences: ManagePreferencesUseCase(preferences: preferences),
            manageServerAddress: ManageServerAddressUseCase(store: address),
        )
    }

    @Test func `loads the saved settings and saves changes`() async {
        let store = StoredPreferences(AppPreferences(warningsEnabled: true, dataSharingEnabled: false))
        let viewModel = makeViewModel(preferences: store)

        await viewModel.load()
        let loaded = viewModel.preferences
        await viewModel.setWarningsEnabled(false)
        await viewModel.setDataSharingEnabled(true)

        #expect(loaded == AppPreferences(warningsEnabled: true, dataSharingEnabled: false))
        #expect(viewModel.isLoaded)
        #expect(await store.load() == AppPreferences(warningsEnabled: false, dataSharingEnabled: true))
    }

    @Test func `shows and saves the server address`() async {
        let address = StoredAddress(URL(string: "https://old-mac.ts.net"))
        let viewModel = makeViewModel(address: address)

        await viewModel.load()
        let shown = viewModel.serverAddress
        viewModel.serverAddress = "https://my-mac.tail1234.ts.net"
        await viewModel.saveServerAddress()

        #expect(shown == "https://old-mac.ts.net")
        #expect(viewModel.serverAddressStatus == .saved)
        #expect(await address.load()?.host() == "my-mac.tail1234.ts.net")
    }

    @Test func `an invalid server address isn't saved`() async {
        let address = StoredAddress()
        let viewModel = makeViewModel(address: address)

        viewModel.serverAddress = "my-mac"
        await viewModel.saveServerAddress()

        #expect(viewModel.serverAddressStatus == .invalid)
        #expect(await address.load() == nil)
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

private actor StoredAddress: ServerAddressStore {
    private var address: URL?

    init(_ address: URL? = nil) {
        self.address = address
    }

    func load() async -> URL? {
        address
    }

    func save(_ address: URL?) async {
        self.address = address
    }
}
