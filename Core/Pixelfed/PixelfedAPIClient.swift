// PixelfedAPIClient.swift
// Rosemount
//
// Pixelfed API client.
// Pixelfed is largely Mastodon-API-compatible, so this client wraps a MastodonAPIClient
// internally and exposes Pixelfed-specific convenience methods on top.
// Swift 5.10 | iOS 17.0+
//
// Types from other files referenced here:
//   MastodonAPIClient  — Defined in MastodonAPIClient.swift
//   MastodonStatus     — Defined in MastodonStatus.swift
//   MastodonVisibility — Defined in MastodonStatus.swift

import Foundation

// MARK: - PixelfedAPIClient

/// Actor-isolated API client for Pixelfed instances.
///
/// Because Pixelfed exposes the Mastodon REST API for nearly all operations,
/// `PixelfedAPIClient` owns a `MastodonAPIClient` instance and delegates the
/// majority of calls to it. Pixelfed-specific functionality (such as photo-album
/// creation) is layered on top via dedicated methods.
actor PixelfedAPIClient {

    // MARK: - Stored Properties

    private let instanceURL: URL
    private let accessToken: String

    /// The underlying Mastodon-compatible client.
    /// Re-created lazily on first access because actors cannot expose stored
    /// non-`Sendable` properties to the outside world; callers should prefer
    /// the dedicated methods on `PixelfedAPIClient` and use `asMastodonClient()`
    /// only when they need an operation not yet wrapped here.
    private let _mastodonClient: MastodonAPIClient

    // MARK: - Init

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
        self._mastodonClient = MastodonAPIClient(
            instanceURL: instanceURL,
            accessToken: accessToken
        )
    }

    // MARK: - Mastodon Client Access

    /// Returns the underlying `MastodonAPIClient` for operations not directly
    /// exposed by `PixelfedAPIClient`.
    ///
    /// Because both actors share the same `instanceURL` and `accessToken` this
    /// is effectively a zero-cost alias.
    func asMastodonClient() -> MastodonAPIClient {
        _mastodonClient
    }

    // MARK: - Photo / Album Posts

    /// Creates a photo post (single image or album) on Pixelfed.
    ///
    /// Pixelfed supports multi-image albums via the standard Mastodon
    /// `media_ids` array; up to four media IDs can be attached per post.
    ///
    /// - Parameters:
    ///   - caption: The post body / alt-text caption.
    ///   - mediaIds: One or more pre-uploaded media attachment IDs.
    ///   - visibility: Post visibility level (defaults to `.public`).
    ///   - sensitive: Whether to mark the media as sensitive.
    ///   - spoilerText: Optional content warning displayed above the media.
    /// - Returns: The newly created `MastodonStatus`.
    func createPhotoPost(
        caption: String,
        mediaIds: [String],
        visibility: MastodonVisibility = .public,
        sensitive: Bool = false,
        spoilerText: String? = nil
    ) async throws -> MastodonStatus {
        try await _mastodonClient.createStatus(
            content: caption,
            visibility: visibility,
            inReplyToId: nil,
            spoilerText: spoilerText,
            sensitive: sensitive,
            mediaIds: mediaIds
        )
    }

    // MARK: - Timeline

    /// Returns the home timeline for the authenticated user.
    ///
    /// Delegates to `MastodonAPIClient.homeTimeline(maxId:sinceId:limit:)`.
    ///
    /// - Parameters:
    ///   - maxId: Return results older than this status ID (pagination cursor).
    ///   - limit: Maximum number of statuses to return (default 20, max 40 on most instances).
    func timeline(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonStatus] {
        try await _mastodonClient.homeTimeline(maxId: maxId, sinceId: nil, limit: limit)
    }

    // MARK: - Accounts

    /// Verifies credentials and returns the authenticated Pixelfed account.
    func verifyCredentials() async throws -> MastodonAccount {
        try await _mastodonClient.verifyCredentials()
    }

    // MARK: - Forwarded Mastodon Operations
    //
    // The methods below are thin pass-throughs provided for discoverability.
    // Callers can also call `asMastodonClient()` and invoke any method directly.

    /// Favourites a status.
    func favouriteStatus(id: String) async throws -> MastodonStatus {
        try await _mastodonClient.favouriteStatus(id: id)
    }

    /// Removes a favourite from a status.
    func unfavouriteStatus(id: String) async throws -> MastodonStatus {
        try await _mastodonClient.unfavouriteStatus(id: id)
    }

    /// Boosts (reblogs) a status.
    func boostStatus(id: String) async throws -> MastodonStatus {
        try await _mastodonClient.boostStatus(id: id)
    }

    /// Removes a boost from a status.
    func unboostStatus(id: String) async throws -> MastodonStatus {
        try await _mastodonClient.unboostStatus(id: id)
    }

    /// Bookmarks a status for the authenticated user.
    func bookmarkStatus(id: String) async throws -> MastodonStatus {
        try await _mastodonClient.bookmarkStatus(id: id)
    }

    /// Follows an account.
    func follow(id: String) async throws -> MastodonRelationship {
        try await _mastodonClient.follow(id: id)
    }

    /// Unfollows an account.
    func unfollow(id: String) async throws -> MastodonRelationship {
        try await _mastodonClient.unfollow(id: id)
    }

    /// Uploads media data and returns the attachment entity.
    func uploadMedia(
        data: Data,
        mimeType: String,
        description: String? = nil
    ) async throws -> MastodonAttachment {
        try await _mastodonClient.uploadMedia(data: data, mimeType: mimeType, description: description)
    }
}
