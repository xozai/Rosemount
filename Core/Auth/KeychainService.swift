// Rosemount — KeychainService.swift
// Generic Keychain wrapper using the Security framework.
// Swift 5.10 | iOS 17.0+

import Foundation
import Security

// MARK: - KeychainError

enum KeychainError: Error, LocalizedError {
    case itemNotFound
    case duplicateItem
    case unexpectedData
    case unhandledError(OSStatus)

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested Keychain item was not found."
        case .duplicateItem:
            return "A Keychain item with this key already exists."
        case .unexpectedData:
            return "The Keychain returned data in an unexpected format."
        case .unhandledError(let status):
            return "Keychain operation failed with OSStatus \(status)."
        }
    }
}

// MARK: - KeychainService

/// A stateless, thread-safe Keychain helper.
/// All methods are `static` because the Security framework APIs are synchronous
/// and do not require actor isolation.
final class KeychainService {

    // MARK: - Private Init

    private init() {}

    // MARK: - Data API

    /// Persists `data` under the given `key` / `service` pair.
    /// Overwrites any existing item with the same key + service.
    static func save(key: String, data: Data, service: String) throws {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecAttrService:      service,
            kSecValueData:        data,
            kSecAttrAccessible:   kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let saveStatus = SecItemAdd(query as CFDictionary, nil)

        if saveStatus == errSecDuplicateItem {
            // Item already exists — update instead.
            let searchQuery: [CFString: Any] = [
                kSecClass:       kSecClassGenericPassword,
                kSecAttrAccount: key,
                kSecAttrService: service
            ]
            let updateAttributes: [CFString: Any] = [
                kSecValueData:      data,
                kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainError.unhandledError(updateStatus)
            }
        } else if saveStatus != errSecSuccess {
            throw KeychainError.unhandledError(saveStatus)
        }
    }

    /// Loads raw `Data` for the given `key` / `service` pair.
    /// Throws `KeychainError.itemNotFound` when no matching item exists.
    static func load(key: String, service: String) throws -> Data {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecAttrService:      service,
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return data
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        default:
            throw KeychainError.unhandledError(status)
        }
    }

    /// Removes the Keychain item matching `key` / `service`.
    /// Throws `KeychainError.itemNotFound` when no matching item exists.
    static func delete(key: String, service: String) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            // errSecItemNotFound is treated as a no-op to keep deletes idempotent.
            return
        default:
            throw KeychainError.unhandledError(status)
        }
    }

    // MARK: - String Convenience API

    /// Encodes `value` as UTF-8 and saves it via `save(key:data:service:)`.
    static func saveString(_ value: String, key: String, service: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.unexpectedData
        }
        try save(key: key, data: data, service: service)
    }

    /// Loads a UTF-8 string saved via `saveString(_:key:service:)`.
    static func loadString(key: String, service: String) throws -> String {
        let data = try load(key: key, service: service)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.unexpectedData
        }
        return string
    }
}
