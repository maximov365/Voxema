import Foundation
import Security
import CryptoKit

// MARK: - SecurityError

/// Typed errors from Keychain and Encryption operations.
/// Messages are content-free — no keys, data, or user PII are ever included.
public enum SecurityError: Error, LocalizedError, Equatable {
    // Keychain
    case keychainItemNotFound
    case keychainWriteFailed(OSStatus)
    case keychainReadFailed(OSStatus)
    case keychainDeleteFailed(OSStatus)
    // Encryption
    case keyGenerationFailed
    case encryptionFailed
    case decryptionFailed
    case invalidSealedBox

    public var errorDescription: String? {
        switch self {
        case .keychainItemNotFound:
            return "Keychain item not found."
        case .keychainWriteFailed(let status):
            return "Keychain write failed (status \(status))."
        case .keychainReadFailed(let status):
            return "Keychain read failed (status \(status))."
        case .keychainDeleteFailed(let status):
            return "Keychain delete failed (status \(status))."
        case .keyGenerationFailed:
            return "Failed to generate encryption key."
        case .encryptionFailed:
            return "Encryption operation failed."
        case .decryptionFailed:
            return "Decryption operation failed."
        case .invalidSealedBox:
            return "Encrypted data is malformed or truncated."
        }
    }
}

// MARK: - KeychainManager

/// Wraps the Security framework for storing, retrieving, and deleting
/// generic password items in the system Keychain.
///
/// Items are keyed by `(service, account)` and stored with
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` to prevent migration
/// via iCloud Keychain (biometric data and encryption keys must stay on-device).
public enum KeychainManager {

    // MARK: Data

    /// Stores `data` in the Keychain under `(service, account)`.
    /// If an item already exists for that key, it is updated in-place.
    public static func store(data: Data, service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        var status = SecItemCopyMatching(query as CFDictionary, nil)

        if status == errSecSuccess || status == errSecInteractionNotAllowed {
            // Update existing item
            let attributes: [CFString: Any] = [kSecValueData: data]
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status != errSecSuccess {
                throw SecurityError.keychainWriteFailed(status)
            }
        } else if status == errSecItemNotFound {
            // Insert new item
            var newItem = baseQuery(service: service, account: account)
            newItem[kSecValueData] = data
            newItem[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(newItem as CFDictionary, nil)
            if status != errSecSuccess {
                throw SecurityError.keychainWriteFailed(status)
            }
        } else {
            throw SecurityError.keychainWriteFailed(status)
        }
    }

    /// Retrieves `Data` stored under `(service, account)`.
    public static func retrieve(service: String, account: String) throws -> Data {
        var query = baseQuery(service: service, account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw SecurityError.keychainItemNotFound
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecurityError.keychainReadFailed(status)
        }
        return data
    }

    /// Deletes the item stored under `(service, account)`.
    /// Silently succeeds if the item does not exist.
    public static func delete(service: String, account: String) throws {
        let query = baseQuery(service: service, account: account)
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw SecurityError.keychainDeleteFailed(status)
        }
    }

    // MARK: String convenience

    /// Stores a UTF-8 encoded `String` in the Keychain.
    public static func storeString(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw SecurityError.keychainWriteFailed(errSecParam)
        }
        try store(data: data, service: service, account: account)
    }

    /// Retrieves a UTF-8 encoded `String` from the Keychain.
    public static func retrieveString(service: String, account: String) throws -> String {
        let data = try retrieve(service: service, account: account)
        guard let value = String(data: data, encoding: .utf8) else {
            throw SecurityError.keychainReadFailed(errSecDecode)
        }
        return value
    }

    // MARK: Private

    private static func baseQuery(service: String, account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}

// MARK: - EncryptionManager

/// AES-256-GCM encryption and decryption using CryptoKit.
///
/// Encryption keys are persisted in the Keychain and auto-generated on first use.
/// The `keyIdentifier` parameter selects which key to use, allowing different
/// keys for different assets (audio files vs. voice profile database).
///
/// Encrypted output is the AES-GCM combined representation (nonce ‖ ciphertext ‖ tag),
/// serialised as raw `Data`.
public enum EncryptionManager {

    private static let keychainService = "com.voxema.app.encryption"

    // MARK: Public API

    /// Encrypts `data` using the key identified by `keyIdentifier`.
    /// The key is auto-generated and stored in the Keychain on first use.
    public static func encrypt(_ data: Data, keyIdentifier: String) throws -> Data {
        let key = try loadOrCreateKey(identifier: keyIdentifier)
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            guard let combined = sealedBox.combined else {
                throw SecurityError.encryptionFailed
            }
            return combined
        } catch let error as SecurityError {
            throw error
        } catch {
            throw SecurityError.encryptionFailed
        }
    }

    /// Decrypts `data` previously encrypted with the key identified by `keyIdentifier`.
    public static func decrypt(_ data: Data, keyIdentifier: String) throws -> Data {
        let key = try loadOrCreateKey(identifier: keyIdentifier)
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: key)
        } catch let error as SecurityError {
            throw error
        } catch CryptoKitError.authenticationFailure {
            throw SecurityError.decryptionFailed
        } catch {
            // Malformed data that couldn't form a SealedBox
            throw SecurityError.invalidSealedBox
        }
    }

    // MARK: Private

    private static func loadOrCreateKey(identifier: String) throws -> SymmetricKey {
        if let existingKeyData = try? KeychainManager.retrieve(service: keychainService, account: identifier) {
            return SymmetricKey(data: existingKeyData)
        }
        // Generate a new 256-bit key
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        do {
            try KeychainManager.store(data: keyData, service: keychainService, account: identifier)
        } catch {
            throw SecurityError.keyGenerationFailed
        }
        return newKey
    }
}
