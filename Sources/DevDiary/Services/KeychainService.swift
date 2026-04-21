import Foundation
import Security
import os.log

/// Minimal Keychain wrapper for storing secrets (e.g., OAuth tokens)
final class KeychainService {
    static let shared = KeychainService()
    private let logger = Logger(subsystem: "com.devdiary", category: "Keychain")
    private init() {}

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case dataConversion
    }

    func setPassword(_ data: Data, service: String, account: String) throws {
        // Delete existing item if present
        try? deletePassword(service: service, account: account)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain set failed: status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func getPassword(service: String, account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            logger.error("Keychain get failed: status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
        guard let data = item as? Data else {
            throw KeychainError.dataConversion
        }
        return data
    }

    func deletePassword(service: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: status=\(status)")
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
