// DoubleRatchet.swift
// Rosemount
//
// Simplified Double Ratchet E2E encryption using CryptoKit.
// Phase 4 implementation — uses Curve25519 + AES-GCM.

import CryptoKit
import Foundation

// MARK: - Errors

enum DoubleRatchetError: Error, LocalizedError {
    case sessionNotInitialized
    case decryptionFailed
    case invalidPublicKey
    case keyDerivationFailed

    var errorDescription: String? {
        switch self {
        case .sessionNotInitialized: return "Ratchet session has not been initialized."
        case .decryptionFailed:     return "Failed to decrypt the message."
        case .invalidPublicKey:     return "The provided public key is invalid."
        case .keyDerivationFailed:  return "Key derivation step failed."
        }
    }
}

// MARK: - RatchetKeyPair

struct RatchetKeyPair {
    let privateKey: Curve25519.KeyAgreement.PrivateKey
    let publicKey: Curve25519.KeyAgreement.PublicKey

    static func generate() -> RatchetKeyPair {
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        return RatchetKeyPair(privateKey: privateKey, publicKey: privateKey.publicKey)
    }
}

// MARK: - RatchetState

struct RatchetState: Codable {
    var rootKey: SymmetricKey
    var sendChainKey: SymmetricKey
    var recvChainKey: SymmetricKey
    var sendCount: Int
    var recvCount: Int
    var remotePublicKey: Curve25519.KeyAgreement.PublicKey?
    /// The local ratchet key pair — only the raw private key bytes are stored.
    var localPrivateKeyData: Data
    var localPublicKeyData: Data

    // MARK: Codable bridging (SymmetricKey / Curve25519 are not natively Codable)

    enum CodingKeys: String, CodingKey {
        case rootKey, sendChainKey, recvChainKey
        case sendCount, recvCount
        case remotePublicKey
        case localPrivateKeyData, localPublicKeyData
    }

    init(
        rootKey: SymmetricKey,
        sendChainKey: SymmetricKey,
        recvChainKey: SymmetricKey,
        sendCount: Int,
        recvCount: Int,
        remotePublicKey: Curve25519.KeyAgreement.PublicKey?,
        localKeyPair: RatchetKeyPair
    ) {
        self.rootKey = rootKey
        self.sendChainKey = sendChainKey
        self.recvChainKey = recvChainKey
        self.sendCount = sendCount
        self.recvCount = recvCount
        self.remotePublicKey = remotePublicKey
        self.localPrivateKeyData = localKeyPair.privateKey.rawRepresentation
        self.localPublicKeyData = localKeyPair.publicKey.rawRepresentation
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rootKeyData       = try c.decode(Data.self, forKey: .rootKey)
        let sendChainKeyData  = try c.decode(Data.self, forKey: .sendChainKey)
        let recvChainKeyData  = try c.decode(Data.self, forKey: .recvChainKey)
        rootKey      = SymmetricKey(data: rootKeyData)
        sendChainKey = SymmetricKey(data: sendChainKeyData)
        recvChainKey = SymmetricKey(data: recvChainKeyData)
        sendCount = try c.decode(Int.self, forKey: .sendCount)
        recvCount = try c.decode(Int.self, forKey: .recvCount)
        localPrivateKeyData = try c.decode(Data.self, forKey: .localPrivateKeyData)
        localPublicKeyData  = try c.decode(Data.self, forKey: .localPublicKeyData)
        if let remoteRaw = try c.decodeIfPresent(Data.self, forKey: .remotePublicKey) {
            remotePublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: remoteRaw)
        } else {
            remotePublicKey = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(rootKey.withUnsafeBytes { Data($0) },       forKey: .rootKey)
        try c.encode(sendChainKey.withUnsafeBytes { Data($0) },  forKey: .sendChainKey)
        try c.encode(recvChainKey.withUnsafeBytes { Data($0) },  forKey: .recvChainKey)
        try c.encode(sendCount,            forKey: .sendCount)
        try c.encode(recvCount,            forKey: .recvCount)
        try c.encode(localPrivateKeyData,  forKey: .localPrivateKeyData)
        try c.encode(localPublicKeyData,   forKey: .localPublicKeyData)
        try c.encodeIfPresent(remotePublicKey?.rawRepresentation, forKey: .remotePublicKey)
    }
}

// MARK: - EncryptedMessage

struct EncryptedMessage: Codable {
    /// AES-GCM ciphertext + authentication tag (combined).
    let ciphertext: Data
    /// AES-GCM nonce (12 bytes).
    let nonce: Data
    /// Sender's current ratchet public key (raw representation).
    let publicKey: Data
    /// Position in the send chain for this message.
    let messageIndex: Int

    // MARK: Base64 JSON helpers for transport

    func encodeToBase64() throws -> String {
        let data = try JSONEncoder().encode(self)
        return data.base64EncodedString()
    }

    static func decodeFromBase64(_ base64: String) throws -> EncryptedMessage {
        guard let data = Data(base64Encoded: base64) else {
            throw DoubleRatchetError.invalidPublicKey
        }
        return try JSONDecoder().decode(EncryptedMessage.self, from: data)
    }
}

// MARK: - DoubleRatchetSession

actor DoubleRatchetSession {
    private var state: RatchetState

    // MARK: Initialization

    init(
        localKeyPair: RatchetKeyPair,
        remotePublicKey: Curve25519.KeyAgreement.PublicKey,
        isInitiator: Bool
    ) throws {
        // Derive an initial shared secret via a single DH exchange.
        let sharedSecret = try localKeyPair.privateKey.sharedSecretFromKeyAgreement(
            with: remotePublicKey
        )

        // Derive root key and the initial chain keys from the shared secret using HKDF.
        let salt = SymmetricKey(size: .bits256)
        let hkdfOutput = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: "RosemountDoubleRatchetInit".data(using: .utf8)!,
            outputByteCount: 96  // 32 bytes × 3
        )
        let keyBytes = hkdfOutput.withUnsafeBytes { Array($0) }
        let rootKey      = SymmetricKey(data: Data(keyBytes[0..<32]))
        let sendChainKey = SymmetricKey(data: Data(keyBytes[32..<64]))
        let recvChainKey = SymmetricKey(data: Data(keyBytes[64..<96]))

        state = RatchetState(
            rootKey: isInitiator ? rootKey : rootKey,
            sendChainKey: isInitiator ? sendChainKey : recvChainKey,
            recvChainKey: isInitiator ? recvChainKey : sendChainKey,
            sendCount: 0,
            recvCount: 0,
            remotePublicKey: remotePublicKey,
            localKeyPair: localKeyPair
        )
    }

    /// Restore a session from a persisted state snapshot.
    init(state: RatchetState) {
        self.state = state
    }

    // MARK: - Public API

    func encrypt(_ plaintext: Data) throws -> EncryptedMessage {
        let (newChainKey, messageKey) = kdfChainKey(state.sendChainKey)
        state.sendChainKey = newChainKey

        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(plaintext, using: messageKey, nonce: nonce)

        let messageIndex = state.sendCount
        state.sendCount += 1

        return EncryptedMessage(
            ciphertext: sealedBox.combined ?? sealedBox.ciphertext + sealedBox.tag,
            nonce: Data(nonce),
            publicKey: state.localPublicKeyData,
            messageIndex: messageIndex
        )
    }

    func decrypt(_ message: EncryptedMessage) throws -> Data {
        // If the sender has ratcheted, perform the DH ratchet step first.
        let currentRemotePublicRaw = state.remotePublicKey?.rawRepresentation
        if message.publicKey != currentRemotePublicRaw {
            guard let newRemoteKey = try? Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: message.publicKey
            ) else {
                throw DoubleRatchetError.invalidPublicKey
            }
            try dhRatchetStep(remotePublicKey: newRemoteKey)
        }

        let (newChainKey, messageKey) = kdfChainKey(state.recvChainKey)
        state.recvChainKey = newChainKey
        state.recvCount += 1

        // Re-assemble the AES-GCM sealed box from the combined ciphertext field.
        guard let sealedBox = try? AES.GCM.SealedBox(combined: message.ciphertext) else {
            throw DoubleRatchetError.decryptionFailed
        }

        do {
            return try AES.GCM.open(sealedBox, using: messageKey)
        } catch {
            throw DoubleRatchetError.decryptionFailed
        }
    }

    /// Expose the current state for persistence.
    func currentState() -> RatchetState {
        return state
    }

    // MARK: - Private Helpers

    private func dhRatchetStep(
        remotePublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws {
        guard
            let localPrivateKey = try? Curve25519.KeyAgreement.PrivateKey(
                rawRepresentation: state.localPrivateKeyData
            )
        else {
            throw DoubleRatchetError.invalidPublicKey
        }

        // Step 1: DH(local, newRemote) → update root key and recv chain key.
        let sharedSecret1 = try localPrivateKey.sharedSecretFromKeyAgreement(
            with: remotePublicKey
        )
        let (newRootKey1, newRecvChainKey) = try hkdfRootKDF(
            rootKey: state.rootKey,
            dhOutput: sharedSecret1,
            info: "RosemountRatchetRecv"
        )

        // Step 2: Generate a new local ratchet key pair.
        let newLocalKeyPair = RatchetKeyPair.generate()

        // Step 3: DH(newLocal, newRemote) → update root key and send chain key.
        let sharedSecret2 = try newLocalKeyPair.privateKey.sharedSecretFromKeyAgreement(
            with: remotePublicKey
        )
        let (newRootKey2, newSendChainKey) = try hkdfRootKDF(
            rootKey: newRootKey1,
            dhOutput: sharedSecret2,
            info: "RosemountRatchetSend"
        )

        state.rootKey          = newRootKey2
        state.recvChainKey     = newRecvChainKey
        state.sendChainKey     = newSendChainKey
        state.remotePublicKey  = remotePublicKey
        state.localPrivateKeyData = newLocalKeyPair.privateKey.rawRepresentation
        state.localPublicKeyData  = newLocalKeyPair.publicKey.rawRepresentation
        state.sendCount        = 0
        state.recvCount        = 0
    }

    /// Derives a new root key and a new chain key from the current root key and a DH output.
    private func hkdfRootKDF(
        rootKey: SymmetricKey,
        dhOutput: SharedSecret,
        info: String
    ) throws -> (SymmetricKey, SymmetricKey) {
        let derived = dhOutput.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: rootKey,
            sharedInfo: info.data(using: .utf8)!,
            outputByteCount: 64
        )
        let bytes = derived.withUnsafeBytes { Array($0) }
        let newRootKey  = SymmetricKey(data: Data(bytes[0..<32]))
        let newChainKey = SymmetricKey(data: Data(bytes[32..<64]))
        return (newRootKey, newChainKey)
    }

    /// KDF for advancing a chain key. Returns (newChainKey, messageKey).
    private func kdfChainKey(
        _ chainKey: SymmetricKey
    ) -> (newChainKey: SymmetricKey, messageKey: SymmetricKey) {
        // Derive message key: HMAC-SHA256(chainKey, 0x01)
        let messageKeyData = HMAC<SHA256>.authenticationCode(
            for: Data([0x01]),
            using: chainKey
        )
        // Derive new chain key: HMAC-SHA256(chainKey, 0x02)
        let newChainKeyData = HMAC<SHA256>.authenticationCode(
            for: Data([0x02]),
            using: chainKey
        )
        return (
            newChainKey: SymmetricKey(data: Data(newChainKeyData)),
            messageKey: SymmetricKey(data: Data(messageKeyData))
        )
    }
}

// MARK: - PublicKeyBundle

/// Transmitted over the network before the first message to bootstrap a session.
struct PublicKeyBundle: Codable {
    let accountId: String
    /// Raw representation of the Curve25519 key-agreement public key.
    let identityKey: Data
    /// Raw representation of a signed pre-key (Curve25519 key-agreement).
    let signedPreKey: Data
    /// Ed25519 signature of `signedPreKey`, produced by `signingKey`.
    let signature: Data
    /// Raw representation of the Ed25519 signing public key used to verify `signature`.
    let signingKey: Data
}

// MARK: - CryptoSessionStore

actor CryptoSessionStore {
    private let keychainService = "com.rosemount.crypto.sessions"
    private var sessions: [String: RatchetState] = [:]

    // MARK: Session Access

    func session(
        for accountId: String,
        localKeyPair: RatchetKeyPair,
        remotePublicKey: Curve25519.KeyAgreement.PublicKey
    ) throws -> DoubleRatchetSession {
        if let existingState = sessions[accountId] {
            return DoubleRatchetSession(state: existingState)
        }
        // Try loading from Keychain.
        if let persistedState = try? loadState(for: accountId) {
            sessions[accountId] = persistedState
            return DoubleRatchetSession(state: persistedState)
        }
        // Create a new session — local party is always the initiator when creating fresh.
        let newSession = try DoubleRatchetSession(
            localKeyPair: localKeyPair,
            remotePublicKey: remotePublicKey,
            isInitiator: true
        )
        let newState = await newSession.currentState()
        sessions[accountId] = newState
        try persistState(for: accountId, state: newState)
        return newSession
    }

    // MARK: Persistence

    func persistState(for accountId: String, state: RatchetState) throws {
        let data = try JSONEncoder().encode(state)
        let key = keychainKey(for: accountId)
        try KeychainService.save(key: key, data: data, service: keychainService)
        sessions[accountId] = state
    }

    func loadState(for accountId: String) throws -> RatchetState? {
        let key = keychainKey(for: accountId)
        guard let data = KeychainService.load(key: key, service: keychainService) else {
            return nil
        }
        return try JSONDecoder().decode(RatchetState.self, from: data)
    }

    // MARK: Private

    private func keychainKey(for accountId: String) -> String {
        return "ratchet_state_\(accountId)"
    }
}
