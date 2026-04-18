import Foundation
import Security

actor KeychainStore {
    static let shared = KeychainStore(service: "com.catinahat85.taylorclaw.apikeys")

    private let service: String

    init(service: String) {
        self.service = service
    }

    enum KeychainError: LocalizedError {
        case unhandled(OSStatus)
        case invalidData

        var errorDescription: String? {
            switch self {
            case .unhandled(let status): "Keychain error \(status)."
            case .invalidData: "Keychain returned invalid data."
            }
        }
    }

    func save(_ key: String, for provider: ProviderID) throws {
        let account = provider.rawValue
        guard let data = key.data(using: .utf8) else { throw KeychainError.invalidData }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus != errSecItemNotFound { throw KeychainError.unhandled(updateStatus) }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.unhandled(addStatus) }
    }

    func load(for provider: ProviderID) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unhandled(status) }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        return string
    }

    func delete(for provider: ProviderID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandled(status)
        }
    }

    func hasKey(for provider: ProviderID) async -> Bool {
        (try? load(for: provider))?.isEmpty == false
    }
}
