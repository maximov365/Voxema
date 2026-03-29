import XCTest
@testable import Voxema

final class SecurityTests: XCTestCase {

    // Use unique service prefixes per test run to avoid Keychain collisions
    private let testService = "com.voxema.test.security.\(UUID().uuidString)"

    override func tearDown() {
        // Best-effort cleanup: remove any test items written during the test
        try? KeychainManager.delete(service: testService, account: "data-test")
        try? KeychainManager.delete(service: testService, account: "string-test")
        try? KeychainManager.delete(service: testService, account: "update-test")
        // Clean up encryption test keys
        try? KeychainManager.delete(service: "com.voxema.app.encryption", account: testService + ".enc-key")
        super.tearDown()
    }

    // MARK: - KeychainManager — Data

    func testKeychainStoreAndRetrieve() throws {
        let original = Data("hello keychain".utf8)
        try KeychainManager.store(data: original, service: testService, account: "data-test")
        let retrieved = try KeychainManager.retrieve(service: testService, account: "data-test")
        XCTAssertEqual(retrieved, original)
    }

    func testKeychainRetrieveNotFound() {
        XCTAssertThrowsError(
            try KeychainManager.retrieve(service: testService, account: "nonexistent")
        ) { error in
            XCTAssertEqual(error as? SecurityError, .keychainItemNotFound)
        }
    }

    func testKeychainUpdate() throws {
        let first  = Data("version-1".utf8)
        let second = Data("version-2".utf8)
        try KeychainManager.store(data: first,  service: testService, account: "update-test")
        try KeychainManager.store(data: second, service: testService, account: "update-test")
        let retrieved = try KeychainManager.retrieve(service: testService, account: "update-test")
        XCTAssertEqual(retrieved, second)
    }

    func testKeychainDelete() throws {
        let data = Data("to-delete".utf8)
        try KeychainManager.store(data: data, service: testService, account: "data-test")
        try KeychainManager.delete(service: testService, account: "data-test")
        XCTAssertThrowsError(
            try KeychainManager.retrieve(service: testService, account: "data-test")
        ) { error in
            XCTAssertEqual(error as? SecurityError, .keychainItemNotFound)
        }
    }

    func testKeychainDeleteNonExistentIsNoOp() {
        // Should not throw for a missing item
        XCTAssertNoThrow(try KeychainManager.delete(service: testService, account: "ghost"))
    }

    // MARK: - KeychainManager — String

    func testKeychainStoreAndRetrieveString() throws {
        let original = "sk-test-api-key-12345"
        try KeychainManager.storeString(original, service: testService, account: "string-test")
        let retrieved = try KeychainManager.retrieveString(service: testService, account: "string-test")
        XCTAssertEqual(retrieved, original)
    }

    // MARK: - EncryptionManager

    func testEncryptDecryptRoundTrip() throws {
        let plaintext = Data("sensitive voice profile data".utf8)
        let keyId = testService + ".enc-key"
        let encrypted = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        XCTAssertNotEqual(encrypted, plaintext, "Ciphertext must differ from plaintext")
        let decrypted = try EncryptionManager.decrypt(encrypted, keyIdentifier: keyId)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptProducesDifferentCiphertextsForSamePlaintext() throws {
        let plaintext = Data("same plaintext".utf8)
        let keyId = testService + ".enc-key"
        let ct1 = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        let ct2 = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        // AES-GCM uses a random nonce per encryption — ciphertexts must differ
        XCTAssertNotEqual(ct1, ct2, "Each encryption should use a fresh nonce")
    }

    func testEncryptedOutputIsLargerThanPlaintext() throws {
        let plaintext = Data("hello".utf8)
        let keyId = testService + ".enc-key"
        let ciphertext = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        // AES-GCM combined = 12-byte nonce + ciphertext + 16-byte tag
        XCTAssertGreaterThan(ciphertext.count, plaintext.count + 12 + 16 - 1)
    }

    func testDecryptWithCorruptedDataThrows() throws {
        let plaintext = Data("real data".utf8)
        let keyId = testService + ".enc-key"
        var ciphertext = try EncryptionManager.encrypt(plaintext, keyIdentifier: keyId)
        // Flip a byte in the ciphertext portion (after the 12-byte nonce)
        ciphertext[20] ^= 0xFF
        XCTAssertThrowsError(try EncryptionManager.decrypt(ciphertext, keyIdentifier: keyId)) { error in
            let secError = error as? SecurityError
            XCTAssertTrue(
                secError == .decryptionFailed || secError == .invalidSealedBox,
                "Expected decryptionFailed or invalidSealedBox, got \(String(describing: error))"
            )
        }
    }

    func testDecryptTruncatedDataThrows() throws {
        let keyId = testService + ".enc-key"
        let truncated = Data(repeating: 0xFF, count: 5)
        XCTAssertThrowsError(try EncryptionManager.decrypt(truncated, keyIdentifier: keyId)) { error in
            let secError = error as? SecurityError
            XCTAssertTrue(
                secError == .decryptionFailed || secError == .invalidSealedBox,
                "Expected decryptionFailed or invalidSealedBox"
            )
        }
    }

    // MARK: - SecurityError

    func testSecurityErrorDescriptionsAreContentFree() {
        let errors: [SecurityError] = [
            .keychainItemNotFound,
            .keychainWriteFailed(-34018),
            .keychainReadFailed(-25300),
            .keychainDeleteFailed(-25300),
            .keyGenerationFailed,
            .encryptionFailed,
            .decryptionFailed,
            .invalidSealedBox,
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            XCTAssertFalse(description.isEmpty, "errorDescription must not be empty")
            XCTAssertFalse(
                description.lowercased().contains("content"),
                "Error description must not mention 'content': \(description)"
            )
        }
    }
}
