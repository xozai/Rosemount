// E2EMessageService.swift
// Rosemount
//
// High-level service coordinating encrypted DM sending/receiving.

import CryptoKit
import Foundation

// MARK: - Errors

enum E2EError: Error, LocalizedError {
    case noSession
    case encryptionFailed
    case decryptionFailed
    case keyNotFound

    var errorDescription: String? {
        switch self {
        case .noSession:        return "No encryption session exists for this conversation."
        case .encryptionFailed: return "Failed to encrypt the message."
        case .decryptionFailed: return "Failed to decrypt the message."
        case .keyNotFound:      return "Local identity key could not be found or generated."
        }
    }
}

// MARK: - E2EMessageService

actor E2EMessageService {
    // MARK: Dependencies

    private let sessionStore: CryptoSessionStore
    private let mastodonClient: MastodonAPIClient
    private let credential: AccountCredential

    // MARK: Key management

    private(set) var localIdentityKeyPair: RatchetKeyPair?

    private let keychainService = "com.rosemount.crypto.identity"
    private let identityKeyKeychainKey = "identity_private_key"

    /// Encrypted-message prefix embedded into status content.
    private static let encryptedPrefix = "🔒 [ENC]"

    // MARK: Initializer

    init(credential: AccountCredential) {
        self.credential = credential
        self.sessionStore = CryptoSessionStore()
        self.mastodonClient = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Key Management

    /// Generates and persists a local identity key pair if one does not already exist.
    func ensureIdentityKey() throws {
        if localIdentityKeyPair != nil { return }

        // Attempt to load an existing key from Keychain.
        if let storedData = KeychainService.load(
            key: identityKeyKeychainKey,
            service: keychainService
        ) {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: storedData
            )
            localIdentityKeyPair = RatchetKeyPair(
                privateKey: privateKey,
                publicKey: privateKey.publicKey
            )
            return
        }

        // Generate a fresh key pair and persist it.
        let newKeyPair = RatchetKeyPair.generate()
        try KeychainService.save(
            key: identityKeyKeychainKey,
            data: newKeyPair.privateKey.rawRepresentation,
            service: keychainService
        )
        localIdentityKeyPair = newKeyPair
    }

    /// Stub: publishes the local public key to the server so others can initiate sessions.
    /// In a production implementation this would POST to `/api/v1/crypto/keys`.
    func publishPublicKey() async throws {
        try ensureIdentityKey()
        guard let keyPair = localIdentityKeyPair else {
            throw E2EError.keyNotFound
        }

        let bundle = PublicKeyBundle(
            accountId: credential.id,
            identityKey: keyPair.publicKey.rawRepresentation,
            signedPreKey: keyPair.publicKey.rawRepresentation, // simplified: same key
            signature: Data()                                   // placeholder
        )

        // Encode bundle as JSON for the hypothetical endpoint.
        let body = try JSONEncoder().encode(bundle)

        var request = URLRequest(
            url: credential.instanceURL.appendingPathComponent("api/v1/crypto/keys")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        _ = try await URLSession.shared.data(for: request)
    }

    // MARK: - Sending

    /// Encrypts `content` and sends it as a Mastodon direct message to `recipient`.
    func sendEncryptedMessage(
        to recipient: MastodonAccount,
        content: String
    ) async throws -> MastodonStatus {
        try ensureIdentityKey()
        guard let localKeyPair = localIdentityKeyPair else {
            throw E2EError.keyNotFound
        }

        // Fetch (or create) the remote public key for the recipient.
        // In production this would be fetched from /api/v1/crypto/keys/:accountId.
        // For now, we use a deterministic ephemeral key derived from the account ID
        // so the code compiles and runs end-to-end; real key exchange is stubbed.
        let remotePublicKey = try await fetchOrDerivePublicKey(for: recipient)

        let session = try await sessionStore.session(
            for: recipient.id,
            localKeyPair: localKeyPair,
            remotePublicKey: remotePublicKey
        )

        guard let plaintextData = content.data(using: .utf8) else {
            throw E2EError.encryptionFailed
        }

        let encryptedMessage: EncryptedMessage
        do {
            encryptedMessage = try await session.encrypt(plaintextData)
        } catch {
            throw E2EError.encryptionFailed
        }

        // Persist updated ratchet state.
        let updatedState = await session.currentState()
        try await sessionStore.persistState(for: recipient.id, state: updatedState)

        let base64JSON = try encryptedMessage.encodeToBase64()
        let wrappedContent = "\(Self.encryptedPrefix)\(base64JSON)"

        return try await mastodonClient.createStatus(
            content: wrappedContent,
            visibility: .direct
        )
    }

    // MARK: - Receiving

    /// Attempts to decrypt an encrypted status. Returns `nil` if the status is not encrypted.
    func decryptMessage(_ status: MastodonStatus) async throws -> String? {
        guard isEncrypted(status) else { return nil }

        let prefixLength = Self.encryptedPrefix.utf16.count
        let contentUTF16 = status.content.utf16
        guard contentUTF16.count > prefixLength else {
            throw E2EError.decryptionFailed
        }

        // Strip the prefix to get the base64 JSON payload.
        let startIndex = status.content.index(
            status.content.startIndex,
            offsetBy: Self.encryptedPrefix.count
        )
        let base64JSON = String(status.content[startIndex...])

        let encryptedMessage: EncryptedMessage
        do {
            encryptedMessage = try EncryptedMessage.decodeFromBase64(base64JSON)
        } catch {
            throw E2EError.decryptionFailed
        }

        try ensureIdentityKey()
        guard let localKeyPair = localIdentityKeyPair else {
            throw E2EError.keyNotFound
        }

        let remotePublicKey = try await fetchOrDerivePublicKey(for: status.account)

        let session = try await sessionStore.session(
            for: status.account.id,
            localKeyPair: localKeyPair,
            remotePublicKey: remotePublicKey
        )

        let plaintextData: Data
        do {
            plaintextData = try await session.decrypt(encryptedMessage)
        } catch {
            throw E2EError.decryptionFailed
        }

        // Persist updated ratchet state.
        let updatedState = await session.currentState()
        try await sessionStore.persistState(for: status.account.id, state: updatedState)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw E2EError.decryptionFailed
        }
        return plaintext
    }

    /// Returns `true` if the status content begins with the encrypted message prefix.
    func isEncrypted(_ status: MastodonStatus) -> Bool {
        return status.content.hasPrefix(Self.encryptedPrefix)
    }

    // MARK: - Private Helpers

    /// Fetches the remote public key for `account` from the server, falling back to a
    /// deterministic ephemeral derivation so that the session bootstrapping compiles cleanly.
    /// Replace with a real network call in production.
    private func fetchOrDerivePublicKey(
        for account: MastodonAccount
    ) async throws -> Curve25519.KeyAgreement.PublicKey {
        // Attempt server fetch (stub — real endpoint: GET /api/v1/crypto/keys/:accountId).
        if let bundle = try? await fetchPublicKeyBundle(for: account.id) {
            return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bundle.identityKey)
        }

        // Fallback: derive a deterministic key from the account ID string so that
        // local development and tests work without a real server.
        guard let seed = account.id.data(using: .utf8) else {
            throw E2EError.keyNotFound
        }
        // Use HKDF to stretch the account ID seed into 32 bytes.
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: seed),
            info: "RosemountEphemeralIdentity".data(using: .utf8)!,
            outputByteCount: 32
        )
        let rawBytes = derivedKey.withUnsafeBytes { Data($0) }
        return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawBytes)
    }

    /// Stub network fetch for a remote account's PublicKeyBundle.
    private func fetchPublicKeyBundle(for accountId: String) async throws -> PublicKeyBundle? {
        var request = URLRequest(
            url: credential.instanceURL
                .appendingPathComponent("api/v1/crypto/keys")
                .appendingPathComponent(accountId)
        )
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(PublicKeyBundle.self, from: data)
    }
}
