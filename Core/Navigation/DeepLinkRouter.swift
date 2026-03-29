// Core/Navigation/DeepLinkRouter.swift
// Observable singleton that receives deep-link intents from push notifications
// and URL callbacks, then drives navigation in AppCoordinator.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MARK: - DeepLinkRouter

/// Central router for deep-link navigation.
///
/// `RosemountApp.handleDeepLink(_:)` and `PushNotificationService` both write to this
/// object. `AppCoordinator` observes it and reacts by switching tabs and pushing views.
@Observable
@MainActor
final class DeepLinkRouter {

    // MARK: - Singleton

    static let shared = DeepLinkRouter()

    // MARK: - Pending Navigations

    /// Tab index to select when a deep link arrives.
    var pendingTab: Int? = nil

    /// Account ID for a profile to open.
    var pendingProfileId: String? = nil

    /// Status ID for a post-detail view to open.
    var pendingStatusId: String? = nil

    /// Conversation ID for a DM thread sheet to open.
    var pendingConversationId: String? = nil

    // MARK: - Init

    private init() {}

    // MARK: - Route Helpers

    /// Routes a `DeepLink` value (from `PushNotificationService`) to pending state.
    func route(_ link: DeepLink, homeTabIndex: Int = 0, notificationsTabIndex: Int = 5) {
        switch link {
        case .profile(let accountId):
            pendingTab = homeTabIndex
            pendingProfileId = accountId
        case .status(let statusId):
            pendingTab = homeTabIndex
            pendingStatusId = statusId
        case .conversation(let conversationId):
            pendingTab = homeTabIndex
            pendingConversationId = conversationId
        case .notifications:
            pendingTab = notificationsTabIndex
        }
    }

    /// Routes a raw `rosemount://` URL (from `onOpenURL`).
    func route(url: URL) {
        guard url.scheme == "rosemount", let host = url.host else { return }
        let pathId = url.pathComponents.dropFirst().first ?? ""

        switch host {
        case "profile" where !pathId.isEmpty:
            pendingTab = 0
            pendingProfileId = pathId
        case "status" where !pathId.isEmpty:
            pendingTab = 0
            pendingStatusId = pathId
        case "conversation" where !pathId.isEmpty:
            pendingTab = 0
            pendingConversationId = pathId
        case "notifications":
            pendingTab = 5
        default:
            break
        }
    }

    /// Consumes all pending navigation state at once. Call after acting on it.
    func consume() {
        pendingTab = nil
        pendingProfileId = nil
        pendingStatusId = nil
        pendingConversationId = nil
    }
}
