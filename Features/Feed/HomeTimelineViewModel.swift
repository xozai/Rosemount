// HomeTimelineViewModel.swift
// Rosemount
//
// ViewModel for the home timeline feed.
// Uses @Observable (Swift 5.10 / iOS 17) and async/await.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MastodonStatus        — defined in Core/Mastodon/Models/MastodonStatus.swift
// MastodonAPIClient     — defined in Core/Mastodon/MastodonAPIClient.swift
// AccountCredential     — defined in Core/Auth/AuthManager.swift
// FederationPlatform    — defined in Core/Auth/AuthManager.swift

// MARK: - FeedType

/// The timeline source shown in the Home tab.
enum FeedType: String, CaseIterable {
    case home      = "Home"
    case local     = "Local"
    case federated = "Federated"

    var icon: String {
        switch self {
        case .home:      return "house"
        case .local:     return "building.2"
        case .federated: return "globe"
        }
    }
}

// MARK: - HomeTimelineViewModel

@Observable
@MainActor
final class HomeTimelineViewModel {

    // MARK: - Published State

    /// All loaded statuses in display order (newest first).
    var statuses: [MastodonStatus] = []

    /// The timeline source currently being shown.
    var feedType: FeedType = .home

    /// `true` while the first page is loading (e.g. on pull-to-refresh or initial load).
    var isLoading: Bool = false

    /// `true` while a subsequent page (load-more) is fetching.
    var isLoadingMore: Bool = false

    /// Non-`nil` when an error has occurred during fetching.
    var error: Error? = nil

    /// `false` once we receive an empty page from the server, preventing redundant requests.
    var hasMore: Bool = true

    // MARK: - Private State

    /// The ID of the oldest loaded status; used as `maxId` when paginating.
    private var oldestId: String? = nil

    /// The API client configured for the current account.
    private var client: MastodonAPIClient? = nil

    // MARK: - Setup

    /// Configures the view-model for a specific authenticated account.
    /// Call this before invoking `refresh()` or `loadMore()`.
    ///
    /// - Parameter credential: The active `AccountCredential`.
    ///   `AccountCredential` is defined in `Core/Auth/AuthManager.swift`.
    func setup(with credential: AccountCredential) {
        // MastodonAPIClient — defined in Core/Mastodon/MastodonAPIClient.swift
        client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
        // Reset pagination state whenever the account changes.
        statuses = []
        oldestId = nil
        hasMore = true
        error = nil
    }

    // MARK: - Refresh (first page)

    /// Switches to a different timeline source and immediately refreshes.
    func switchFeed(to type: FeedType) async {
        guard type != feedType else { return }
        feedType = type
        await refresh()
    }

    /// Clears existing data and fetches the first page of the current timeline.
    func refresh() async {
        guard let client else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil
        oldestId = nil
        hasMore = true

        do {
            let page: [MastodonStatus]
            switch feedType {
            case .home:
                page = try await client.homeTimeline(maxId: nil, limit: 40)
            case .local:
                page = try await client.localTimeline(maxId: nil, limit: 40)
            case .federated:
                page = try await client.federatedTimeline(maxId: nil, limit: 40)
            }
            statuses = page
            oldestId = page.last?.id
            hasMore = !page.isEmpty
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Load More (pagination)

    /// Fetches the next page of statuses and appends them to the list.
    /// Uses `oldestId` as the `maxId` cursor for Mastodon's link-based pagination.
    func loadMore() async {
        guard let client else { return }
        guard !isLoadingMore, !isLoading, hasMore else { return }

        isLoadingMore = true
        error = nil

        do {
            let page: [MastodonStatus]
            switch feedType {
            case .home:
                page = try await client.homeTimeline(maxId: oldestId, limit: 40)
            case .local:
                page = try await client.localTimeline(maxId: oldestId, limit: 40)
            case .federated:
                page = try await client.federatedTimeline(maxId: oldestId, limit: 40)
            }
            if page.isEmpty {
                hasMore = false
            } else {
                // Deduplicate before appending (in case of race conditions).
                let existingIDs = Set(statuses.map(\.id))
                let newStatuses = page.filter { !existingIDs.contains($0.id) }
                statuses.append(contentsOf: newStatuses)
                oldestId = page.last?.id
            }
        } catch {
            self.error = error
        }

        isLoadingMore = false
    }

    // MARK: - Toggle Favourite

    /// Optimistically toggles the favourite state, then syncs with the server.
    ///
    /// - Parameter status: The status to toggle.
    func toggleFavourite(_ status: MastodonStatus) async {
        guard let client else { return }

        // Optimistic update — swap the local copy immediately.
        applyOptimisticUpdate(id: status.id) { s in
            s.favourited ? s.withFavouritesCount(s.favouritesCount - 1).withFavourited(false)
                         : s.withFavouritesCount(s.favouritesCount + 1).withFavourited(true)
        }

        do {
            let updated: MastodonStatus
            if status.favourited {
                updated = try await client.unfavouriteStatus(id: status.id)
            } else {
                updated = try await client.favouriteStatus(id: status.id)
            }
            // Replace with authoritative server response.
            applyServerUpdate(updated)
        } catch {
            // Roll back the optimistic update on failure.
            applyServerUpdate(status)
            self.error = error
        }
    }

    // MARK: - Boost (reblog)

    /// Optimistically toggles the boost (reblog) state, then syncs with the server.
    ///
    /// - Parameter status: The status to boost or un-boost.
    func boost(_ status: MastodonStatus) async {
        guard let client else { return }

        // Optimistic update.
        applyOptimisticUpdate(id: status.id) { s in
            s.reblogged ? s.withReblogsCount(s.reblogsCount - 1).withReblogged(false)
                        : s.withReblogsCount(s.reblogsCount + 1).withReblogged(true)
        }

        do {
            let updated: MastodonStatus
            if status.reblogged {
                updated = try await client.unboostStatus(id: status.id)
            } else {
                updated = try await client.boostStatus(id: status.id)
            }
            applyServerUpdate(updated)
        } catch {
            applyServerUpdate(status)
            self.error = error
        }
    }

    // MARK: - Private Helpers

    /// Applies a pure transformation to the status with the given ID in `statuses`.
    private func applyOptimisticUpdate(id: String, transform: (MastodonStatus) -> MastodonStatus) {
        guard let index = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[index] = transform(statuses[index])
    }

    /// Replaces the matching status in `statuses` with an updated server copy.
    private func applyServerUpdate(_ updated: MastodonStatus) {
        guard let index = statuses.firstIndex(where: { $0.id == updated.id }) else { return }
        statuses[index] = updated
    }
}
