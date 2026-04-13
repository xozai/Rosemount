// CryptoRatchetTests.swift
// Rosemount
//
// Unit tests for the Double Ratchet E2E encryption implementation.
// Tests: round-trip encrypt/decrypt, wrong-key decryption failure,
// multi-message chains, and EncryptedMessage base64 serialisation.
//
// Swift 5.10 | iOS 17.0+

import XCTest
import CryptoKit
@testable import Rosemount

final class CryptoRatchetTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a matched pair of sessions (initiator and responder)
    /// sharing a Curve25519 key agreement.
    private func makeSessionPair() throws -> (initiator: DoubleRatchetSession, responder: DoubleRatchetSession) {
        let aliceKeyPair = RatchetKeyPair.generate()
        let bobKeyPair   = RatchetKeyPair.generate()

        let initiator = try DoubleRatchetSession(
            localKeyPair: aliceKeyPair,
            remotePublicKey: bobKeyPair.publicKey,
            isInitiator: true
        )
        let responder = try DoubleRatchetSession(
            localKeyPair: bobKeyPair,
            remotePublicKey: aliceKeyPair.publicKey,
            isInitiator: false
        )
        return (initiator, responder)
    }

    // MARK: - Round-trip encrypt / decrypt

    func testEncryptDecryptRoundTrip() async throws {
        let (sender, receiver) = try makeSessionPair()

        let plaintext = "Hello, Rosemount!".data(using: .utf8)!
        let encrypted = try await sender.encrypt(plaintext)
        let decrypted = try await receiver.decrypt(encrypted)

        XCTAssertEqual(decrypted, plaintext)
        XCTAssertEqual(String(data: decrypted, encoding: .utf8), "Hello, Rosemount!")
    }

    func testEncryptDecryptEmptyData() async throws {
        let (sender, receiver) = try makeSessionPair()

        let plaintext = Data()
        let encrypted = try await sender.encrypt(plaintext)
        let decrypted = try await receiver.decrypt(encrypted)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptLargePayload() async throws {
        let (sender, receiver) = try makeSessionPair()

        let plaintext = Data(repeating: 0xAB, count: 65_536)
        let encrypted = try await sender.encrypt(plaintext)
        let decrypted = try await receiver.decrypt(encrypted)

        XCTAssertEqual(decrypted, plaintext)
    }

    func testEncryptDecryptUnicodeString() async throws {
        let (sender, receiver) = try makeSessionPair()

        let original = "🌿 Rosemount — Community Social on the Open Web 🌐"
        let plaintext = original.data(using: .utf8)!
        let encrypted = try await sender.encrypt(plaintext)
        let decrypted = try await receiver.decrypt(encrypted)

        XCTAssertEqual(String(data: decrypted, encoding: .utf8), original)
    }

    // MARK: - Multiple sequential messages

    func testMultipleMessagesSameSession() async throws {
        let (sender, receiver) = try makeSessionPair()

        let messages = ["First", "Second", "Third", "Fourth"]
        for message in messages {
            let data = message.data(using: .utf8)!
            let encrypted = try await sender.encrypt(data)
            let decrypted = try await receiver.decrypt(encrypted)
            XCTAssertEqual(String(data: decrypted, encoding: .utf8), message)
        }
    }

    // MARK: - Decryption with wrong key fails

    func testDecryptWithWrongKeyThrows() async throws {
        let aliceKeyPair = RatchetKeyPair.generate()
        let bobKeyPair   = RatchetKeyPair.generate()
        let carolKeyPair = RatchetKeyPair.generate()

        // Sender (Alice) expects to communicate with Bob
        let sender = try DoubleRatchetSession(
            localKeyPair: aliceKeyPair,
            remotePublicKey: bobKeyPair.publicKey,
            isInitiator: true
        )

        // Carol has a completely different key pair — cannot decrypt Alice's messages
        let wrongReceiver = try DoubleRatchetSession(
            localKeyPair: carolKeyPair,
            remotePublicKey: aliceKeyPair.publicKey,
            isInitiator: false
        )

        let plaintext = "Secret message".data(using: .utf8)!
        let encrypted = try await sender.encrypt(plaintext)

        do {
            _ = try await wrongReceiver.decrypt(encrypted)
            XCTFail("Decryption with wrong key should have thrown")
        } catch let error as DoubleRatchetError {
            // Expected: either decryptionFailed or invalidPublicKey
            XCTAssertTrue(
                error == .decryptionFailed || error == .invalidPublicKey,
                "Unexpected error: \(error)"
            )
        }
    }

    // MARK: - Ciphertext is not plaintext

    func testEncryptedDataDiffersFromPlaintext() async throws {
        let (sender, _) = try makeSessionPair()

        let plaintext = "Do not store plaintext".data(using: .utf8)!
        let encrypted = try await sender.encrypt(plaintext)

        XCTAssertNotEqual(encrypted.ciphertext, plaintext)
    }

    // MARK: - Nonce uniqueness

    func testEachMessageHasUniqueNonce() async throws {
        let (sender, _) = try makeSessionPair()

        let plaintext = "Test".data(using: .utf8)!
        let msg1 = try await sender.encrypt(plaintext)
        let msg2 = try await sender.encrypt(plaintext)

        XCTAssertNotEqual(msg1.nonce, msg2.nonce)
    }

    // MARK: - Message index increments

    func testMessageIndexIncrements() async throws {
        let (sender, _) = try makeSessionPair()

        let plaintext = "x".data(using: .utf8)!
        let msg0 = try await sender.encrypt(plaintext)
        let msg1 = try await sender.encrypt(plaintext)
        let msg2 = try await sender.encrypt(plaintext)

        XCTAssertEqual(msg0.messageIndex, 0)
        XCTAssertEqual(msg1.messageIndex, 1)
        XCTAssertEqual(msg2.messageIndex, 2)
    }

    // MARK: - EncryptedMessage base64 serialisation

    func testEncryptedMessageBase64RoundTrip() async throws {
        let (sender, receiver) = try makeSessionPair()

        let plaintext = "Serialise me".data(using: .utf8)!
        let encrypted = try await sender.encrypt(plaintext)

        // Encode to base64, then decode back
        let base64 = try encrypted.encodeToBase64()
        XCTAssertFalse(base64.isEmpty)

        let decoded = try EncryptedMessage.decodeFromBase64(base64)
        XCTAssertEqual(decoded.ciphertext, encrypted.ciphertext)
        XCTAssertEqual(decoded.nonce, encrypted.nonce)
        XCTAssertEqual(decoded.messageIndex, encrypted.messageIndex)

        // The decoded message should still decrypt correctly
        let decrypted = try await receiver.decrypt(decoded)
        XCTAssertEqual(decrypted, plaintext)
    }

    func testInvalidBase64ThrowsOnDecode() {
        XCTAssertThrowsError(try EncryptedMessage.decodeFromBase64("not-valid-base64!!!")) { error in
            XCTAssertTrue(error is DoubleRatchetError)
        }
    }

    // MARK: - RatchetKeyPair generation

    func testKeyPairGeneratesUniqueKeys() {
        let kp1 = RatchetKeyPair.generate()
        let kp2 = RatchetKeyPair.generate()
        XCTAssertNotEqual(kp1.publicKey.rawRepresentation, kp2.publicKey.rawRepresentation)
        XCTAssertNotEqual(kp1.privateKey.rawRepresentation, kp2.privateKey.rawRepresentation)
    }

    func testKeyPairPublicKeyMatchesPrivate() {
        let kp = RatchetKeyPair.generate()
        // The public key derived from the private key should match
        let derived = kp.privateKey.publicKey
        XCTAssertEqual(kp.publicKey.rawRepresentation, derived.rawRepresentation)
    }

    // MARK: - RatchetState Codable round-trip

    func testRatchetStateCodeableRoundTrip() async throws {
        let (session, _) = try makeSessionPair()
        let state = await session.currentState()

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RatchetState.self, from: encoded)

        XCTAssertEqual(state.sendCount, decoded.sendCount)
        XCTAssertEqual(state.recvCount, decoded.recvCount)
        XCTAssertEqual(state.localPublicKeyData, decoded.localPublicKeyData)
        XCTAssertEqual(state.localPrivateKeyData, decoded.localPrivateKeyData)

        // Symmetric keys should survive the round-trip
        let originalRootBytes = state.rootKey.withUnsafeBytes { Data($0) }
        let decodedRootBytes  = decoded.rootKey.withUnsafeBytes { Data($0) }
        XCTAssertEqual(originalRootBytes, decodedRootBytes)
    }
}
