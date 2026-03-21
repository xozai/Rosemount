// CachedStatus.swift
// Rosemount
//
// SwiftData model for caching timeline posts locally.
// Mirrors the essential fields of MastodonStatus (defined in Core/Mastodon/Models/MastodonStatus.swift)
// in a persistable, query-friendly form.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import SwiftData

// MARK: - CachedStatus

// TODO: MastodonStatus  — defined in Core/Mastodon/Models/MastodonStatus.swift
// TODO: MastodonAccount — defined in Core/Mastodon/Models/MastodonStatus.swift
// TODO: MastodonAttachment — defined in Core/Mastodon/Models/MastodonStatus.swift

@Model
final class CachedStatus {

    // MARK: Identity

    /// The Mastodon status ID.  Unique per timeline type.
    @Attribute(.unique) var id: String

    /// The ActivityPub URI for this status.
    var uri: String

    /// The canonical HTML permalink URL, if available.
    var url: String?

    // MARK: Timestamps

    /// When the status was originally created on the remote server.
    var createdAt: Date

    /// When this cache entry was last fetched from the network.
    var fetchedAt: Date

    // MARK: Content

    /// HTML content string as returned by the Mastodon API.
    var content: String

    /// Content-Warning / spoiler text; empty string when absent.
    var spoilerText: String

    /// Whether the post is marked sensitive.
    var sensitive: Bool

    /// Audience visibility: "public", "unlisted", "private", or "direct".
    var visibility: String

    // MARK: Engagement counts

    var favouritesCount: Int
    var reblogsCount: Int
    var repliesCount: Int

    // MARK: Viewer-relative state

    var favourited: Bool
    var reblogged: Bool
    var bookmarked: Bool
    var pinned: Bool

    // MARK: Author (denormalized for cache read performance)

    /// The Mastodon account ID of the author.
    var authorId: String

    /// Full handle in `@user@instance` form.
    var authorHandle: String

    var authorDisplayName: String

    /// Remote URL string for the author's avatar image.
    var authorAvatarURL: String?

    // MARK: Media

    /// JSON-encoded `[MastodonAttachment]` array, or `nil` when there are no attachments.
    /// Encoded/decoded via `CachedStatus.mediaAttachments` helpers below.
    var mediaAttachmentsJSON: String?

    // MARK: Feed context

    /// The timeline feed this entry belongs to: "home", "local", "federated", "community".
    var timelineType: String

    /// Non-nil when `timelineType == "community"`.
    var communityId: String?

    // MARK: - Init

    init(
        id: String,
        uri: String,
        url: String? = nil,
        createdAt: Date,
        content: String,
        spoilerText: String = "",
        sensitive: Bool = false,
        visibility: String = "public",
        favouritesCount: Int = 0,
        reblogsCount: Int = 0,
        repliesCount: Int = 0,
        favourited: Bool = false,
        reblogged: Bool = false,
        bookmarked: Bool = false,
        pinned: Bool = false,
        authorId: String,
        authorHandle: String,
        authorDisplayName: String,
        authorAvatarURL: String? = nil,
        mediaAttachmentsJSON: String? = nil,
        timelineType: String,
        communityId: String? = nil,
        fetchedAt: Date = Date()
    ) {
        self.id                   = id
        self.uri                  = uri
        self.url                  = url
        self.createdAt            = createdAt
        self.content              = content
        self.spoilerText          = spoilerText
        self.sensitive            = sensitive
        self.visibility           = visibility
        self.favouritesCount      = favouritesCount
        self.reblogsCount         = reblogsCount
        self.repliesCount         = repliesCount
        self.favourited           = favourited
        self.reblogged            = reblogged
        self.bookmarked           = bookmarked
        self.pinned               = pinned
        self.authorId             = authorId
        self.authorHandle         = authorHandle
        self.authorDisplayName    = authorDisplayName
        self.authorAvatarURL      = authorAvatarURL
        self.mediaAttachmentsJSON = mediaAttachmentsJSON
        self.timelineType         = timelineType
        self.communityId          = communityId
        self.fetchedAt            = fetchedAt
    }
}

// MARK: - Factory

extension CachedStatus {

    /// Creates a `CachedStatus` from a live `MastodonStatus` network response.
    ///
    /// - Parameters:
    ///   - status: The source network model.  `MastodonStatus` is defined in
    ///             `Core/Mastodon/Models/MastodonStatus.swift`.
    ///   - timelineType: The feed context label ("home", "local", "federated", "community").
    ///   - communityId: Required only when `timelineType == "community"`.
    /// - Returns: A fully populated `CachedStatus` ready for insertion into the SwiftData context.
    static func from(
        _ status: MastodonStatus,
        timelineType: String,
        communityId: String? = nil
    ) -> CachedStatus {

        // --- Encode media attachments to JSON ---
        var mediaJSON: String? = nil
        if !status.mediaAttachments.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            if let data = try? encoder.encode(status.mediaAttachments),
               let jsonString = String(data: data, encoding: .utf8) {
                mediaJSON = jsonString
            }
        }

        // --- Resolve author from the reblog or the top-level status ---
        let author: MastodonAccount = status.reblog?.account ?? status.account

        // --- Parse createdAt ---
        let createdAt = ISO8601DateFormatter().date(from: status.createdAt) ?? Date()

        return CachedStatus(
            id:                   status.id,
            uri:                  status.uri,
            url:                  status.url,
            createdAt:            createdAt,
            content:              status.content,
            spoilerText:          status.spoilerText,
            sensitive:            status.sensitive,
            visibility:           status.visibility,
            favouritesCount:      status.favouritesCount,
            reblogsCount:         status.reblogsCount,
            repliesCount:         status.repliesCount,
            favourited:           status.favourited,
            reblogged:            status.reblogged,
            bookmarked:           status.bookmarked,
            pinned:               status.pinned ?? false,
            authorId:             author.id,
            authorHandle:         author.acct,
            authorDisplayName:    author.displayName,
            authorAvatarURL:      author.avatarURL,
            mediaAttachmentsJSON: mediaJSON,
            timelineType:         timelineType,
            communityId:          communityId,
            fetchedAt:            Date()
        )
    }
}

// MARK: - Media helpers

extension CachedStatus {

    /// Decodes the `mediaAttachmentsJSON` field into a typed array.
    /// Returns an empty array if there is no JSON or decoding fails.
    ///
    /// `MastodonAttachment` is defined in `Core/Mastodon/Models/MastodonStatus.swift`.
    func decodedMediaAttachments() -> [MastodonAttachment] {
        guard let json = mediaAttachmentsJSON,
              let data = json.data(using: .utf8) else {
            return []
        }
        return (try? JSONDecoder().decode([MastodonAttachment].self, from: data)) ?? []
    }
}
