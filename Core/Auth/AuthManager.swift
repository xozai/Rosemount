// Rosemount — AuthManager.swift
// Central authentication state manager.
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MARK: - FederationPlatform

enum FederationPlatform: String, Codable, CaseIterable {
    case mastodon   = "mastodon"
    case pixelfed   = "pixelfed"
    case rosemount  = "rosemount"
}

// MARK: - AccountCredential

/// Represents a single authenticated account on any supported federation platform.
struct AccountCredential: Codable, Identifiable, Hashable {
    let id: UUID
    let handle: String
    let instanceURL: URL
    let accessToken: String
    let tokenType: String
    let scope: String
    let platform: FederationPlatform

    // Optional fields populated after verifying credentials
    let actorURL: URL?
    let displayName: String?
    let avatarURL: URL?

    // MARK: - Init

    init(
        id: UUID = UUID(),
        handle: String,
        instanceURL: URL,
        accessToken: String,
        tokenType: String,
        scope: String,
        platform: FederationPlatform,
        actorURL: URL? = nil,
        displayName: String? = nil,
        avatarURL: URL? = nil
    ) {
        self.id = id
        self.handle = handle
        self.instanceURL = instanceURL
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.scope = scope
        self.platform = platform
        self.actorURL = actorURL
        self.displayName = displayName
        self.avatarURL = avatarURL
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: AccountCredential, rhs: AccountCredential) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - AuthManager

/// Central, observable authentication state manager.
///
/// `@Observable` requires the class to be on the MainActor for safe property observation
/// from SwiftUI views. Use `AuthManager.shared` as the singleton entry point.
@MainActor
@Observable
final class AuthManager {

    // MARK: - Singleton

    static let shared = AuthManager()

    // MARK: - Keychain Constants

    private enum KeychainKeys {
        static let accountsKey = "rosemount.auth.accounts"
        static let activeAccountIDKey = "rosemount.auth.activeAccountID"
        static let service = "com.rosemount.app"
    }

    // MARK: - Observable State

    /// All accounts the user has authenticated with.
    private(set) var accounts: [AccountCredential] = []

    /// The currently active account used for API calls.
    private(set) var activeAccount: AccountCredential?

    /// Convenience flag; `true` when at least one account is authenticated.
    var isAuthenticated: Bool {
        activeAccount != nil
    }

    // MARK: - Init

    private init() {
        loadAccounts()
    }

    // MARK: - Public API

    /// Adds a new account credential and makes it the active account.
    /// If an account with the same `id` already exists it is replaced.
    func addAccount(_ credential: AccountCredential) {
        if let existingIndex = accounts.firstIndex(where: { $0.id == credential.id }) {
            accounts[existingIndex] = credential
        } else {
            accounts.append(credential)
        }
        activeAccount = credential
        persistAccounts()
        Task { await PushNotificationService.shared.requestAuthorization() }
    }

    /// Removes an account credential.
    /// If the removed account was active, the first remaining account becomes active.
    func removeAccount(_ credential: AccountCredential) {
        accounts.removeAll { $0.id == credential.id }
        if activeAccount?.id == credential.id {
            activeAccount = accounts.first
        }
        persistAccounts()
    }

    /// Changes the currently active account.
    func switchAccount(to credential: AccountCredential) {
        guard accounts.contains(where: { $0.id == credential.id }) else { return }
        activeAccount = credential
        persistAccounts()
    }

    /// Signs out all accounts and clears persisted state.
    func signOut() {
        accounts.removeAll()
        activeAccount = nil
        clearPersistedAccounts()
    }

    // MARK: - Persistence

    /// Serialises the accounts array and the active account ID to the Keychain.
    private func persistAccounts() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let accountsData = try encoder.encode(accounts)
            try KeychainService.save(
                key: KeychainKeys.accountsKey,
                data: accountsData,
                service: KeychainKeys.service
            )

            if let activeID = activeAccount?.id {
                let idString = activeID.uuidString
                try KeychainService.saveString(
                    idString,
                    key: KeychainKeys.activeAccountIDKey,
                    service: KeychainKeys.service
                )
            } else {
                try? KeychainService.delete(
                    key: KeychainKeys.activeAccountIDKey,
                    service: KeychainKeys.service
                )
            }
        } catch {
            // Keychain errors during persistence should not crash the app.
            // Log the error in a real implementation.
            assertionFailure("AuthManager: Failed to persist accounts — \(error.localizedDescription)")
        }
    }

    /// Deserialises accounts and the active account ID from the Keychain on startup.
    private func loadAccounts() {
        do {
            let data = try KeychainService.load(
                key: KeychainKeys.accountsKey,
                service: KeychainKeys.service
            )
            let decoder = JSONDecoder()
            let loadedAccounts = try decoder.decode([AccountCredential].self, from: data)
            accounts = loadedAccounts

            // Restore active account
            if let idString = try? KeychainService.loadString(
                key: KeychainKeys.activeAccountIDKey,
                service: KeychainKeys.service
            ), let uuid = UUID(uuidString: idString) {
                activeAccount = loadedAccounts.first { $0.id == uuid } ?? loadedAccounts.first
            } else {
                activeAccount = loadedAccounts.first
            }
        } catch KeychainError.itemNotFound {
            // First launch — no accounts stored yet.
            accounts = []
            activeAccount = nil
        } catch {
            assertionFailure("AuthManager: Failed to load accounts — \(error.localizedDescription)")
            accounts = []
            activeAccount = nil
        }
    }

    /// Removes all Keychain items managed by `AuthManager`.
    private func clearPersistedAccounts() {
        try? KeychainService.delete(key: KeychainKeys.accountsKey, service: KeychainKeys.service)
        try? KeychainService.delete(key: KeychainKeys.activeAccountIDKey, service: KeychainKeys.service)
    }
}
