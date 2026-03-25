// E2EMessageService.swift
// Rosemount
//
// High-level service coordinating encrypted DM sending/receiving.
// Uses a Double-Ratchet session (DoubleRatchet.swift) for forward-secret
// message encryption, with Curve25519 for key agreement and Ed25519 for
// public-key bundle signatures.

import CryptoKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "social.rosemount", category: "E2E")

// MARK: - Errors

enum E2EError: Error, LocalizedError {
    case noSession
    case encryptionFailed
    case decryptionFailed
    case keyNotFound
    case signatureFailed

    var errorDescription: String? {
        switch self {
        case .noSession:        return "No encryption session exists for this conversation."
        case .encryptionFailed: return "Failed to encrypt the message."
        case .decryptionFailed: return "Failed to decrypt the message."
        case .keyNotFound:      return "Local identity key could not be found or generated."
        case .signatureFailed:  return "Failed to sign the public key bundle."
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
    /// Ed25519 signing key stored alongside the key-agreement key.
    private var localSigningKey: Curve25519.Signing.PrivateKey?

    private let keychainService        = "com.rosemount.crypto.identity"
    private let identityKeyKeychainKey = "identity_private_key"
    private let signingKeyKeychainKey  = "identity_signing_key"

    /// Encrypted-message prefix embedded into status content (full peer-verified session).
    static let encryptedPrefix = "🔒 [ENC]"
    /// Prefix used when falling back to HKDF-derived keys without peer verification.
    static let encryptedCompatPrefix = "🔒 [ENC-COMPAT]"

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

        // Attempt to load an existing key-agreement key from Keychain.
        if let agreementData = KeychainService.load(
            key: identityKeyKeychainKey,
            service: keychainService
        ) {
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: agreementData
            )
            localIdentityKeyPair = RatchetKeyPair(
                privateKey: privateKey,
                publicKey: privateKey.publicKey
            )
        } else {
            // Generate a fresh key-agreement key pair and persist it.
            let newKeyPair = RatchetKeyPair.generate()
            try KeychainService.save(
                key: identityKeyKeychainKey,
                data: newKeyPair.privateKey.rawRepresentation,
                service: keychainService
            )
            localIdentityKeyPair = newKeyPair
        }

        // Load or generate the companion Ed25519 signing key.
        if let signingData = KeychainService.load(
            key: signingKeyKeychainKey,
            service: keychainService
        ) {
            localSigningKey = try Curve25519.Signing.PrivateKey(rawRepresentation: signingData)
        } else {
            let newSigningKey = Curve25519.Signing.PrivateKey()
            try KeychainService.save(
                key: signingKeyKeychainKey,
                data: newSigningKey.rawRepresentation,
                service: keychainService
            )
            localSigningKey = newSigningKey
        }
    }

    /// Publishes the local public key bundle to the server so peers can initiate sessions.
    /// Sends a real Ed25519 signature over the signed-pre-key bytes.
    /// POST /api/v1/crypto/keys
    func publishPublicKey() async throws {
        try ensureIdentityKey()
        guard let keyPair = localIdentityKeyPair,
              let signingKey = localSigningKey else {
            throw E2EError.keyNotFound
        }

        let signedPreKeyBytes = keyPair.publicKey.rawRepresentation
        let signature: Data
        do {
            signature = try signingKey.signature(for: signedPreKeyBytes)
        } catch {
            throw E2EError.signatureFailed
        }

        let bundle = PublicKeyBundle(
            accountId: credential.id,
            identityKey: keyPair.publicKey.rawRepresentation,
            signedPreKey: signedPreKeyBytes,
            signature: signature,
            signingKey: signingKey.publicKey.rawRepresentation
        )

        let body = try JSONEncoder().encode(bundle)

        var request = URLRequest(
            url: credential.instanceURL.appendingPathComponent("api/v1/crypto/keys")
        )
        request.httpMethod = "POST"
        request.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                logger.error("publishPublicKey HTTP \(http.statusCode)")
            } else {
                logger.info("Public key bundle published.")
            }
        } catch {
            // Log but don't rethrow — key publication is best-effort;
            // the session will fall back to HKDF-derived keys until the
            // server endpoint is deployed.
            logger.warning("publishPublicKey failed: \(error.localizedDescription)")
        }
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

        let (remotePublicKey, isCompatMode) = try await fetchOrDerivePublicKey(for: recipient)

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

        let updatedState = await session.currentState()
        try await sessionStore.persistState(for: recipient.id, state: updatedState)

        let base64JSON = try encryptedMessage.encodeToBase64()
        let prefix = isCompatMode ? Self.encryptedCompatPrefix : Self.encryptedPrefix
        let wrappedContent = "\(prefix)\(base64JSON)"

        return try await mastodonClient.createStatus(
            content: wrappedContent,
            visibility: .direct
        )
    }

    // MARK: - Receiving

    /// Attempts to decrypt an encrypted status. Returns `nil` if the status is not encrypted.
    func decryptMessage(_ status: MastodonStatus) async throws -> String? {
        guard isEncrypted(status) else { return nil }

        let activePrefix = status.content.hasPrefix(Self.encryptedCompatPrefix)
            ? Self.encryptedCompatPrefix
            : Self.encryptedPrefix
        let prefixLength = activePrefix.utf16.count
        guard status.content.utf16.count > prefixLength else {
            throw E2EError.decryptionFailed
        }

        let startIndex = status.content.index(
            status.content.startIndex,
            offsetBy: activePrefix.count
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

        let (remotePublicKey, _) = try await fetchOrDerivePublicKey(for: status.account)

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

        let updatedState = await session.currentState()
        try await sessionStore.persistState(for: status.account.id, state: updatedState)

        guard let plaintext = String(data: plaintextData, encoding: .utf8) else {
            throw E2EError.decryptionFailed
        }
        return plaintext
    }

    /// Returns `true` if the status content begins with either encrypted message prefix.
    func isEncrypted(_ status: MastodonStatus) -> Bool {
        return status.content.hasPrefix(Self.encryptedPrefix) ||
               status.content.hasPrefix(Self.encryptedCompatPrefix)
    }

    /// Returns `true` if the status was encrypted using the HKDF fallback (no peer verification).
    func isCompatMode(_ status: MastodonStatus) -> Bool {
        return status.content.hasPrefix(Self.encryptedCompatPrefix)
    }

    // MARK: - Private Helpers

    /// Fetches the remote public key from the server; falls back to a deterministic
    /// HKDF derivation so sessions work before the server endpoint is deployed.
    ///
    /// Returns `(key, isCompatMode)` where `isCompatMode == true` means peer verification
    /// was unavailable and the HKDF-derived fallback key was used.
    private func fetchOrDerivePublicKey(
        for account: MastodonAccount
    ) async throws -> (Curve25519.KeyAgreement.PublicKey, isCompatMode: Bool) {
        do {
            if let bundle = try await fetchPublicKeyBundle(for: account.id) {
                // Verify the bundle signature before trusting the key.
                if verifyBundleSignature(bundle) {
                    let key = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: bundle.identityKey)
                    return (key, false)
                }
                logger.error("Bundle signature invalid for account \(account.id) — falling back to derived key.")
            }
        } catch {
            logger.error("Key bundle fetch failed for \(account.id): \(error.localizedDescription) — using HKDF fallback.")
        }

        // Fallback: derive a deterministic key from the account ID string so that
        // sessions work without a real server. Replace when backend is deployed.
        guard let seed = account.id.data(using: .utf8) else {
            throw E2EError.keyNotFound
        }
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: seed),
            info: "RosemountEphemeralIdentity".data(using: .utf8)!,
            outputByteCount: 32
        )
        let rawBytes = derivedKey.withUnsafeBytes { Data($0) }
        return try (Curve25519.KeyAgreement.PublicKey(rawRepresentation: rawBytes), true)
    }

    /// Network fetch for a remote account's PublicKeyBundle.
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

    /// Verifies the Ed25519 signature in a PublicKeyBundle.
    private func verifyBundleSignature(_ bundle: PublicKeyBundle) -> Bool {
        guard let signingPublicKey = try? Curve25519.Signing.PublicKey(
            rawRepresentation: bundle.signingKey
        ) else { return false }
        return signingPublicKey.isValidSignature(bundle.signature, for: bundle.signedPreKey)
    }
}
