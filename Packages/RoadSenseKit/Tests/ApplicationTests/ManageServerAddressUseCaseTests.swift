import Application
import Foundation
import Testing

struct ManageServerAddressUseCaseTests {
    @Test(arguments: ["https://my-mac.tail1234.ts.net", "  http://10.0.0.5:8080 "])
    func `saves a valid address`(text: String) async throws {
        let store = MemoryAddressStore()
        let manage = ManageServerAddressUseCase(store: store)

        try await manage.save(text)

        #expect(await manage()?.absoluteString == text.trimmingCharacters(in: .whitespaces))
    }

    @Test(arguments: ["my-mac.ts.net", "ftp://my-mac.ts.net", "https://", "not a url"])
    func `rejects what isn't an http address`(text: String) async {
        let manage = ManageServerAddressUseCase(store: MemoryAddressStore())

        await #expect(throws: ServerAddressError.invalid) {
            try await manage.save(text)
        }
    }

    @Test func `an empty address clears the override`() async throws {
        let store = MemoryAddressStore()
        let manage = ManageServerAddressUseCase(store: store)
        try await manage.save("https://my-mac.ts.net")

        try await manage.save("  ")

        #expect(await manage() == nil)
    }
}

private actor MemoryAddressStore: ServerAddressStore {
    private var address: URL?

    func load() async -> URL? {
        address
    }

    func save(_ address: URL?) async {
        self.address = address
    }
}
