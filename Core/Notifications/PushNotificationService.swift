// PushNotificationService.swift
// Rosemount
//
// APNs push notification registration and deep-link routing.
// Handles device token registration, permission requests, badge management,
// and parsing of incoming notification payloads into typed DeepLink values.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation
import UserNotifications
import UIKit

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
            print("[PushNotificationService] Authorization request failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Device Token

    /// Converts the raw APNs device-token `Data` into a lowercase hex string and
    /// stores it in `deviceToken`.
    ///
    /// Call this from `application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`.
    func handleDeviceToken(_ data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        deviceToken = hex
        print("[PushNotificationService] Device token registered: \(hex)")
        // TODO: register token with Rosemount server
        // Example: await RosemountAPIClient.shared.registerPushToken(hex, for: AuthManager.shared.activeAccount)
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
            print("[PushNotificationService] Failed to set badge count: \(error.localizedDescription)")
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
