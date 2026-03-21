// CommunityDetailViewModel.swift
// Rosemount
//
// ViewModel for the community detail / home screen.
// Manages the community metadata, pinned posts, paginated feed, and join/leave actions.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// RosemountCommunity    — defined in Core/Communities/Models/RosemountCommunity.swift
// CommunityPinnedPost   — defined in Core/Communities/Models/CommunityMember.swift
// MastodonStatus        — defined in Core/Mastodon/Models/MastodonStatus.swift
// CommunityAPIClient    — defined in Core/Communities/CommunityAPIClient.swift
// AccountCredential     — defined in Core/Auth/AuthManager.swift

// MARK: - CommunityDetailViewModel

@Observable
@MainActor
final class CommunityDetailViewModel {

    // MARK: - Published State

    /// The full community metadata; populated after `refresh()`.
    var community: RosemountCommunity? = nil

    /// Posts pinned to the top of the feed by admins / moderators.
    var pinnedPosts: [CommunityPinnedPost] = []

    /// Feed statuses loaded in chronological (newest-first) order.
    var feedStatuses: [MastodonStatus] = []

    /// `true` during the initial or pull-to-refresh load.
    var isLoading: Bool = false

    /// `true` while a paginated "load more" request is in flight.
    var isLoadingMore: Bool = false

    /// Non-`nil` when an error occurred; used to drive an alert.
    var error: Error? = nil

    /// `false` once we receive an empty page, preventing redundant pagination calls.
    var hasMore: Bool = true

    /// Controls the post composer sheet presented from the toolbar.
    var showingPostComposer: Bool = false

    // MARK: - Computed Properties

    /// `true` when the active user is a member and therefore allowed to post.
    var canPost: Bool {
        community?.isMember == true
    }

    /// `true` when the active user has moderator (or admin) rights to pin/unpin posts.
    var canPin: Bool {
        community?.isModerator == true
    }

    /// `true` when the active user is a community admin and can access settings.
    var canManage: Bool {
        community?.isAdmin == true
    }

    // MARK: - Private State

    private var slug: String = ""

    /// The oldest status ID loaded; used as the `maxId` pagination cursor.
    private var oldestId: String? = nil

    private var client: CommunityAPIClient?

    // MARK: - Setup

    /// Configures the view-model for a specific community and authenticated account.
    ///
    /// - Parameters:
    ///   - slug:        The URL-safe community slug.
    ///   - credential:  The active `AccountCredential`.
    func setup(slug: String, credential: AccountCredential) {
        self.slug  = slug
        self.client = CommunityAPIClient(credential: credential)
        // Reset state on reconfiguration.
        community   = nil
        pinnedPosts = []
        feedStatuses = []
        oldestId    = nil
        hasMore     = true
        error       = nil
    }

    // MARK: - Refresh

    /// Loads the community metadata, pinned posts, and first feed page concurrently
    /// using `async let` structured concurrency.
    func refresh() async {
        guard let client, !slug.isEmpty else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil
        oldestId = nil
        hasMore  = true

        do {
            async let communityFetch = client.community(slug: slug)
            async let pinnedFetch    = client.pinnedPosts(slug: slug)
            async let feedFetch      = client.communityFeed(slug: slug, maxId: nil, limit: 40)

            let (communityResult, pinnedResult, feedResult) = try await (
                communityFetch,
                pinnedFetch,
                feedFetch
            )

            community    = communityResult
            pinnedPosts  = pinnedResult
            feedStatuses = feedResult
            oldestId     = feedResult.last?.id
            hasMore      = !feedResult.isEmpty
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Load More (pagination)

    /// Fetches the next page of the community feed and appends it to `feedStatuses`.
    func loadMore() async {
        guard let client, !slug.isEmpty else { return }
        guard !isLoadingMore, !isLoading, hasMore else { return }

        isLoadingMore = true
        error = nil

        do {
            let page = try await client.communityFeed(slug: slug, maxId: oldestId, limit: 40)
            if page.isEmpty {
                hasMore = false
            } else {
                let existingIDs = Set(feedStatuses.map(\.id))
                let newStatuses = page.filter { !existingIDs.contains($0.id) }
                feedStatuses.append(contentsOf: newStatuses)
                oldestId = page.last?.id
            }
        } catch {
            self.error = error
        }

        isLoadingMore = false
    }

    // MARK: - Join

    /// Optimistically marks the user as a member, then syncs with the server.
    func join() async {
        guard let client, let community else { return }

        // Optimistic update.
        self.community = community.withMembership(isMember: true, role: .member)

        do {
            let updated = try await client.joinCommunity(slug: community.slug)
            self.community = updated
        } catch {
            // Roll back.
            self.community = community
            self.error = error
        }
    }

    // MARK: - Leave

    /// Removes the active user from this community.
    func leave() async {
        guard let client, let community else { return }

        // Optimistic update.
        self.community = community.withMembership(isMember: false, role: nil)

        do {
            try await client.leaveCommunity(slug: community.slug)
        } catch {
            // Roll back.
            self.community = community
            self.error = error
        }
    }
}

// MARK: - RosemountCommunity + Optimistic Copy

extension RosemountCommunity {

    /// Returns a copy of this community with `isMember` and `myRole` patched.
    func withMembership(isMember: Bool, role: CommunityRole?) -> RosemountCommunity {
        RosemountCommunity(
            id:            id,
            slug:          slug,
            name:          name,
            description:   description,
            avatarURL:     avatarURL,
            headerURL:     headerURL,
            isPrivate:     isPrivate,
            memberCount:   memberCount,
            postCount:     postCount,
            createdAt:     createdAt,
            instanceHost:  instanceHost,
            myRole:        role,
            isMember:      isMember,
            isPinned:      isPinned,
            pinnedPostIds: pinnedPostIds
        )
    }
}
