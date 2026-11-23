import Application
import Domain
import Foundation
import Security

/// Keeps the anonymous device id in the Keychain, on this device only (it isn't synced or restored elsewhere).
public actor KeychainDeviceIdentityStore: DeviceIdentityStore {
    private let service: String
    private var cached: DeviceID?

    /// - Parameter service: Keychain service name; tests pass their own so they don't touch the app's id.
    public init(service: String = "com.hkamal.RoadSense.deviceID") {
        self.service = service
    }

    public func deviceID() throws -> DeviceID {
        if let cached {
            return cached
        }
        let id = try read() ?? create()
        cached = id
        return id
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "deviceID",
        ]
    }

    private func read() throws -> DeviceID? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status != errSecItemNotFound else { return nil }
        guard status == errSecSuccess, let data = result as? Data, let text = String(data: data, encoding: .utf8),
              let uuid = UUID(uuidString: text)
        else { throw DeviceIdentityError.storageUnavailable }
        return DeviceID(rawValue: uuid)
    }

    private func create() throws -> DeviceID {
        let id = DeviceID(rawValue: UUID())
        var attributes = baseQuery
        attributes[kSecValueData as String] = Data(id.rawValue.uuidString.utf8)
        // Readable while locked (drives end with the phone in a pocket), and never leaves this device.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw DeviceIdentityError.storageUnavailable }
        return id
    }
}
