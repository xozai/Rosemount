// NotificationsViewModel.swift
// Rosemount
//
// Observable view-model backing the in-app notification centre.
// Handles pagination, filter state, and badge management.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MastodonAPIClient        — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonNotification     — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonNotificationType — defined in Core/Mastodon/MastodonAPIClient.swift
// AccountCredential        — defined in Core/Auth/AuthManager.swift
// PushNotificationService  — defined in Core/Notifications/PushNotificationService.swift

// MARK: - NotificationFilter

/// Segmented filter applied to the notifications list.
enum NotificationFilter: String, CaseIterable, Identifiable {

    case all          = "all"
    case mentions     = "mentions"
    case follows      = "follows"
    case boosts       = "boosts"
    case favourites   = "favourites"

    var id: String { rawValue }

    /// Human-readable label shown in the filter chip.
    var title: String {
        switch self {
        case .all:        return "All"
        case .mentions:   return "Mentions"
        case .follows:    return "Follows"
        case .boosts:     return "Boosts"
        case .favourites: return "Favourites"
        }
    }

    /// Returns `true` when the given notification should be included under this filter.
    func includes(_ notification: MastodonNotification) -> Bool {
        switch self {
        case .all:
            return true
        case .mentions:
            return notification.type == .mention
        case .follows:
            return notification.type == .follow || notification.type == .followRequest
        case .boosts:
            return notification.type == .reblog
        case .favourites:
            return notification.type == .favourite
        }
    }
}

// MARK: - NotificationsViewModel

/// Observable view-model for the in-app notification centre.
///
/// Responsibilities:
/// - Fetches paginated notifications from `MastodonAPIClient`.
/// - Applies the active `NotificationFilter` client-side.
/// - Clears the app badge when notifications are viewed.
@Observable
@MainActor
final class NotificationsViewModel {

    // MARK: - Observable State

    /// The full, unfiltered notification list fetched from the API.
    var notifications: [MastodonNotification] = []

    /// `true` while the initial / refresh load is in flight.
    var isLoading: Bool = false

    /// `true` while a "load more" (pagination) request is in flight.
    var isLoadingMore: Bool = false

    /// Non-nil when the most recent network operation failed.
    var error: Error?

    /// Whether there are likely more notifications to page in.
    var hasMore: Bool = true

    /// The active filter chip selection.
    var filter: NotificationFilter = .all

    // MARK: - Private State

    /// The `id` of the oldest fetched notification — used as `max_id` for the
    /// next page request.
    private var oldestId: String?

    /// Lazily initialised once `setup(with:)` is called.
    private var client: MastodonAPIClient?

    // MARK: - Computed Properties

    /// The subset of `notifications` that passes the current `filter`.
    var filteredNotifications: [MastodonNotification] {
        notifications.filter { filter.includes($0) }
    }

    // MARK: - Setup

    /// Configures the API client from the provided credential.
    /// Must be called before any fetch methods.
    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Data Loading

    /// Refreshes the notification list from the beginning (page 1).
    /// Replaces the current `notifications` array on success.
    func refresh() async {
        guard let client else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil
        oldestId = nil
        hasMore = true

        do {
            let fetched = try await client.notifications(maxId: nil, limit: 40)
            notifications = fetched
            oldestId = fetched.last?.id
            hasMore = !fetched.isEmpty
            // Clear badge when the user opens the notification centre.
            await PushNotificationService.shared.clearBadge()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    /// Appends the next page of notifications using `oldestId` as the cursor.
    /// No-ops when `hasMore` is `false` or a load is already in flight.
    func loadMore() async {
        guard let client else { return }
        guard hasMore, !isLoading, !isLoadingMore else { return }

        isLoadingMore = true

        do {
            let fetched = try await client.notifications(maxId: oldestId, limit: 40)
            if fetched.isEmpty {
                hasMore = false
            } else {
                // De-duplicate by ID before appending.
                let existingIds = Set(notifications.map(\.id))
                let newItems = fetched.filter { !existingIds.contains($0.id) }
                notifications.append(contentsOf: newItems)
                oldestId = fetched.last?.id
                hasMore = fetched.count == 40
            }
        } catch {
            self.error = error
        }

        isLoadingMore = false
    }

    /// Clears all notifications on the server and resets the local badge to 0.
    func markAllRead() async {
        await PushNotificationService.shared.clearBadge()
        // POST /api/v1/notifications/clear — dismisses all notifications server-side.
        try? await client?.clearAllNotifications()
    }
}
