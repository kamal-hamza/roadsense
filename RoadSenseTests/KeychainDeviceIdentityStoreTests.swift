import Foundation
import Infrastructure
import Security
import Testing

/// Runs here, inside the app, because package tests in the Simulator have no Keychain access.
struct KeychainDeviceIdentityStoreTests {
    @Test func `creates one id and keeps returning it`() async throws {
        let service = "KeychainDeviceIdentityStoreTests-\(UUID().uuidString)"

        let first = try await KeychainDeviceIdentityStore(service: service).deviceID()
        let again = try await KeychainDeviceIdentityStore(service: service).deviceID()
        // Clean up so test runs don't pile up Keychain items.
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)

        #expect(first == again)
    }
}
