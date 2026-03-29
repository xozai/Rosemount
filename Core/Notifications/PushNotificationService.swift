// PushNotificationService.swift
// Rosemount
//
// APNs push notification registration and deep-link routing.
// Handles device token registration, permission requests, badge management,
// and parsing of incoming notification payloads into typed DeepLink values.
//
// Swift 5.10 | iOS 17.0+

import CryptoKit
import Foundation
import OSLog
import Observation
import Security
import UserNotifications
import UIKit

private let logger = Logger(subsystem: "social.rosemount", category: "PushNotifications")

// MARK: - DeepLink

/// Typed deep-link destinations that can be parsed from a push notification payload
/// or constructed elsewhere in the app for programmatic navigation.
enum DeepLink: Equatable {
    /// Navigate to a user's profile page.
    case profile(accountId: String)
    /// Navigate to a specific status / post.
    case status(statusId: String)
    /// Navigate to a specific DM conversation.
    case conversation(conversationId: String)
    /// Navigate to the in-app notification centre.
    case notifications
}

// MARK: - PushNotificationService

/// Singleton service that manages APNs registration, device-token lifecycle,
/// badge counts, and routing of incoming push payloads to typed `DeepLink` values.
///
/// Call `requestAuthorization()` once the user has signed in.
/// Wire `handleDeviceToken(_:)` and `handleNotification(_:)` from your
/// `AppDelegate` / `UNUserNotificationCenterDelegate` callbacks.
@MainActor
@Observable
final class PushNotificationService: NSObject {

    // MARK: - Singleton

    static let shared = PushNotificationService()

    // MARK: - Observable State

    /// The hex-encoded APNs device token after a successful registration.
    /// `nil` until `registerForRemoteNotifications` callback fires.
    var deviceToken: String?

    /// A deep-link queued from a cold-start notification tap, ready for the
    /// root navigation coordinator to consume on first appearance.
    var pendingDeepLink: DeepLink?

    // MARK: - Init

    private override init() {
        super.init()
    }

    // MARK: - Authorization

    /// Requests authorisation for alert, badge and sound notifications from the user.
    ///
    /// - Returns: `true` when the user granted permission (or had already granted it),
    ///   `false` when they denied or an error occurred.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            if granted {
                // Must be called on the main thread — @MainActor guarantees this.
                UIApplication.shared.registerForRemoteNotifications()
            }
            return granted
        } catch {
            logger.error("Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Device Token

    /// Converts the raw APNs device-token `Data` into a lowercase hex string,
    /// stores it in `deviceToken`, and registers it with the Rosemount backend.
    ///
    /// Call this from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func handleDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        logger.debug("Device token received (\(hex.prefix(8))…)")
        Task { await registerTokenWithServer(hex) }
    }

    /// POSTs the device token to the Rosemount push-notification relay server,
    /// then subscribes directly to Mastodon Web Push for each authenticated account.
    ///
    /// The relay server receives APNs tokens and forwards Mastodon Web Push payloads.
    /// The direct Mastodon subscription ensures in-app notifications also work
    /// when the relay is unavailable.
    private func registerTokenWithServer(_ token: String) async {
        guard let account = AuthManager.shared.activeAccount else { return }

        // 1. Register with the Rosemount relay server.
        let endpoint = URL(string: "https://api.rosemount.social/api/v1/push/register")!
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(account.accessToken)", forHTTPHeaderField: "Authorization")

        let payload: [String: Any] = [
            "token":        token,
            "platform":     "apns",
            "environment":  "production",
            "instance_url": account.instanceURL.absoluteString,
            "account_id":   account.handle,
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                logger.error("Token registration returned HTTP \(http.statusCode)")
            } else {
                logger.info("Push token registered with relay server.")
            }
        } catch {
            logger.error("Relay registration failed: \(error.localizedDescription)")
        }

        // 2. Subscribe to Mastodon Web Push directly on each account's instance.
        await subscribeWebPush(for: account, deviceToken: token)
    }

    /// Subscribes to Mastodon Web Push (`POST /api/v1/push/subscription`) for the given account.
    ///
    /// Generates (or retrieves from Keychain) a P-256 keypair and auth secret for
    /// end-to-end encryption of push payloads.
    private func subscribeWebPush(for account: AccountCredential, deviceToken: String) async {
        let keychainTag = "social.rosemount.push.\(account.id.uuidString)"

        // Retrieve or generate the P-256 keypair.
        let (p256dhKey, authSecret): (String, String)
        do {
            (p256dhKey, authSecret) = try loadOrCreatePushKeys(tag: keychainTag)
        } catch {
            logger.error("Failed to create/load push keys: \(error.localizedDescription)")
            return
        }

        // Build the relay endpoint URL for this account.
        let pushEndpoint = "https://api.rosemount.social/api/v1/push/relay/\(account.id.uuidString)/\(deviceToken)"

        let mastodonClient = MastodonAPIClient(
            instanceURL: account.instanceURL,
            accessToken: account.accessToken
        )
        do {
            try await mastodonClient.subscribePushNotifications(
                endpoint: pushEndpoint,
                p256dhKey: p256dhKey,
                authSecret: authSecret
            )
            logger.info("Mastodon Web Push subscription created for \(account.handle).")
        } catch {
            logger.error("Web Push subscription failed for \(account.handle): \(error.localizedDescription)")
        }
    }

    // MARK: - Push Key Management

    /// Returns the base64url-encoded P-256 public key and auth secret for push encryption,
    /// generating and storing them in the Keychain if they don't exist yet.
    private func loadOrCreatePushKeys(tag: String) throws -> (p256dhKey: String, authSecret: String) {
        let keyTag     = "\(tag).key"
        let secretTag  = "\(tag).secret"

        // Try loading existing key from Keychain.
        if let existingKey = keychainLoad(tag: keyTag),
           let existingSecret = keychainLoad(tag: secretTag) {
            return (existingKey, existingSecret)
        }

        // Generate a new P-256 private key and a 16-byte auth secret.
        let privateKey = P256.KeyAgreement.PrivateKey()
        let p256dhKey = privateKey.publicKey.rawRepresentation.base64URLEncoded()

        var authSecretBytes = [UInt8](repeating: 0, count: 16)
        let _ = SecRandomCopyBytes(kSecRandomDefault, 16, &authSecretBytes)
        let authSecret = Data(authSecretBytes).base64URLEncoded()

        // Store the raw private key scalar + auth secret in Keychain.
        try keychainStore(data: privateKey.rawRepresentation, tag: keyTag)
        try keychainStore(data: Data(authSecretBytes), tag: secretTag)

        return (p256dhKey, authSecret)
    }

    // MARK: - Keychain Helpers

    private func keychainStore(data: Data, tag: String) throws {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrAccount:     tag,
            kSecValueData:       data,
            kSecAttrAccessible:  kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private func keychainLoad(tag: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:           kSecClassGenericPassword,
            kSecAttrAccount:     tag,
            kSecReturnData:      true,
            kSecMatchLimit:      kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        // Try to interpret as P-256 private key (32-byte raw scalar) — re-derive public key.
        if data.count == 32,
           let privateKey = try? P256.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return privateKey.publicKey.rawRepresentation.base64URLEncoded()
        }
        // Otherwise treat it as a raw value (auth secret or unknown).
        return data.base64URLEncoded()
    }

    // MARK: - Notification Payload Routing

    /// Parses an incoming remote notification's `userInfo` dictionary into a
    /// typed `DeepLink`.
    ///
    /// Expected keys in the Mastodon Web Push payload:
    /// - `"type"` → `"mention"`, `"follow"`, `"favourite"`, `"reblog"`, `"poll"`, etc.
    /// - `"status_id"` → ID string of the related status (if applicable).
    /// - `"account_id"` → ID string of the actor who triggered the notification.
    /// - `"conversation_id"` → ID string of the related DM conversation (if applicable).
    ///
    /// - Returns: The appropriate `DeepLink`, or `nil` when the payload is unrecognised.
    @discardableResult
    func handleNotification(_ userInfo: [AnyHashable: Any]) -> DeepLink? {
        let type         = userInfo["type"]            as? String
        let statusId     = userInfo["status_id"]       as? String
        let accountId    = userInfo["account_id"]      as? String
        let conversationId = userInfo["conversation_id"] as? String

        let deepLink: DeepLink?

        switch type {
        case "mention", "status", "reblog", "favourite", "poll", "update":
            if let statusId {
                deepLink = .status(statusId: statusId)
            } else if let accountId {
                deepLink = .profile(accountId: accountId)
            } else {
                deepLink = .notifications
            }

        case "follow", "follow_request":
            if let accountId {
                deepLink = .profile(accountId: accountId)
            } else {
                deepLink = .notifications
            }

        case "direct":
            if let conversationId {
                deepLink = .conversation(conversationId: conversationId)
            } else {
                deepLink = .notifications
            }

        default:
            // Unrecognised type — fall back to the notification centre.
            deepLink = type != nil ? .notifications : nil
        }

        pendingDeepLink = deepLink
        if let deepLink {
            DeepLinkRouter.shared.route(deepLink)
        }
        return deepLink
    }

    // MARK: - Badge Management

    /// Sets the app's badge count via `UNUserNotificationCenter`.
    ///
    /// iOS 17+ requires calling `setBadgeCount(_:)` on the notification centre;
    /// setting `UIApplication.shared.applicationIconBadgeNumber` is deprecated.
    func setBadgeCount(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            logger.error("Failed to set badge count: \(error.localizedDescription)")
        }
    }

    /// Clears the app badge (sets it to 0).
    func clearBadge() async {
        await setBadgeCount(0)
    }

    // MARK: - Pending Deep Link Consumption

    /// Consumes and returns the pending deep link, clearing it from state.
    /// The navigation coordinator should call this on launch/foreground.
    func consumePendingDeepLink() -> DeepLink? {
        defer { pendingDeepLink = nil }
        return pendingDeepLink
    }
}

// MARK: - Data + Base64URL

private extension Data {
    /// Returns a base64url-encoded string (URL-safe, no padding) as per RFC 4648 §5.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
