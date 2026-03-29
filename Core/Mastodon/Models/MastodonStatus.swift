// MastodonStatus.swift
// Rosemount
//
// Mastodon Status (post) model matching the Mastodon REST API v1 response schema.
// Reference: https://docs.joinmastodon.org/entities/Status/
// Swift 5.10 | iOS 17.0+

import Foundation

// MastodonAccount — Defined in MastodonAccount.swift
// MastodonEmoji  — Defined in MastodonAccount.swift

// MARK: - MastodonVisibility

/// Controls who can see a status.
enum MastodonVisibility: String, Codable, CaseIterable {
    case `public`  = "public"
    case unlisted  = "unlisted"
    case `private` = "private"
    case direct    = "direct"
}

// MARK: - MastodonAttachmentType

enum MastodonAttachmentType: String, Codable {
    case image   = "image"
    case gifv    = "gifv"
    case video   = "video"
    case audio   = "audio"
    case unknown = "unknown"
}

// MARK: - MastodonAttachment

/// A media attachment (image, video, audio, gifv) associated with a status.
struct MastodonAttachment: Codable, Identifiable, Hashable {
    let id: String
    let type: MastodonAttachmentType
    let url: String
    let previewUrl: String?
    let remoteUrl: String?
    /// Alt-text / accessibility description.
    let description: String?
    let blurhash: String?
    /// Raw metadata dictionary — structure varies per media type.
    let meta: AttachmentMeta?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case url
        case previewUrl  = "preview_url"
        case remoteUrl   = "remote_url"
        case description
        case blurhash
        case meta
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MastodonAttachment, rhs: MastodonAttachment) -> Bool { lhs.id == rhs.id }
}

/// Simplified metadata container that captures common width/height info.
struct AttachmentMeta: Codable, Hashable {
    let width: Int?
    let height: Int?
    let aspect: Double?
    let duration: Double?
    let fps: Int?
}

// MARK: - MastodonMention

/// A mention of a user within a status.
struct MastodonMention: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let url: String
    let acct: String

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MastodonMention, rhs: MastodonMention) -> Bool { lhs.id == rhs.id }
}

// MARK: - MastodonTag

/// A hashtag referenced in a status.
struct MastodonTag: Codable, Hashable {
    let name: String
    let url: String
}

// MARK: - MastodonApplication

/// The application that posted the status.
struct MastodonApplication: Codable, Hashable {
    let name: String
    let website: String?
}

// MARK: - MastodonPollOption

struct MastodonPollOption: Codable, Hashable {
    let title: String
    /// `nil` if the poll has not expired and the authenticated user has not voted.
    let votesCount: Int?

    enum CodingKeys: String, CodingKey {
        case title
        case votesCount = "votes_count"
    }
}

// MARK: - MastodonPoll

/// An interactive poll attached to a status.
struct MastodonPoll: Codable, Identifiable, Hashable {
    let id: String
    /// ISO 8601 expiry timestamp. `nil` means the poll never expires.
    let expiresAt: String?
    let expired: Bool
    let multiple: Bool
    let votesCount: Int
    let votersCount: Int?
    let voted: Bool?
    let ownVotes: [Int]?
    let options: [MastodonPollOption]

    enum CodingKeys: String, CodingKey {
        case id
        case expiresAt   = "expires_at"
        case expired
        case multiple
        case votesCount  = "votes_count"
        case votersCount = "voters_count"
        case voted
        case ownVotes    = "own_votes"
        case options
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MastodonPoll, rhs: MastodonPoll) -> Bool { lhs.id == rhs.id }
}

// MARK: - MastodonCard

/// An OpenGraph preview card for a URL referenced in a status.
struct MastodonCard: Codable, Hashable {
    let url: String
    let title: String
    let description: String
    let type: String
    let image: String?
    let providerName: String?

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case description
        case type
        case image
        case providerName = "provider_name"
    }
}

// MARK: - MastodonStatus

/// A single Mastodon post (status).
///
/// The `reblog` property is marked `indirect` via a wrapper to avoid a direct recursive struct;
/// here we use a class-backed approach through optional reference.
struct MastodonStatus: Codable, Identifiable, Hashable {

    let id: String
    let uri: String
    let url: String?
    /// ISO 8601 timestamp string.
    let createdAt: String
    /// The account that authored (or reblogged) this status.
    let account: MastodonAccount
    /// HTML-formatted post body.
    let content: String
    let visibility: MastodonVisibility
    let sensitive: Bool
    /// Content warning / subject line.
    let spoilerText: String
    let mediaAttachments: [MastodonAttachment]
    let application: MastodonApplication?
    let mentions: [MastodonMention]
    let tags: [MastodonTag]
    let emojis: [MastodonEmoji]
    let reblogsCount: Int
    let favouritesCount: Int
    let repliesCount: Int
    /// The status being reblogged, if this is a boost.
    let reblog: MastodonStatusWrapper?
    let poll: MastodonPoll?
    let card: MastodonCard?
    let language: String?
    /// Plain-text source content (only returned by edit/history endpoints).
    let text: String?
    /// ISO 8601 timestamp string; present when a status has been edited.
    let editedAt: String?

    // MARK: Authenticated-User Relationship Flags (optional — absent when not authenticated)
    let favourited: Bool?
    let reblogged: Bool?
    let muted: Bool?
    let bookmarked: Bool?
    let pinned: Bool?

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case uri
        case url
        case createdAt          = "created_at"
        case account
        case content
        case visibility
        case sensitive
        case spoilerText        = "spoiler_text"
        case mediaAttachments   = "media_attachments"
        case application
        case mentions
        case tags
        case emojis
        case reblogsCount       = "reblogs_count"
        case favouritesCount    = "favourites_count"
        case repliesCount       = "replies_count"
        case reblog
        case poll
        case card
        case language
        case text
        case editedAt           = "edited_at"
        case favourited
        case reblogged
        case muted
        case bookmarked
        case pinned
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MastodonStatus, rhs: MastodonStatus) -> Bool { lhs.id == rhs.id }
}

// MARK: - MastodonStatusWrapper
//
// Swift structs cannot be directly recursive. We wrap the reblogged status in a
// thin Codable class so that `MastodonStatus` can embed it without infinite layout.

final class MastodonStatusWrapper: Codable, Hashable {
    let status: MastodonStatus

    init(_ status: MastodonStatus) {
        self.status = status
    }

    // Forward Codable to the wrapped MastodonStatus directly.
    required init(from decoder: Decoder) throws {
        status = try MastodonStatus(from: decoder)
    }

    func encode(to encoder: Encoder) throws {
        try status.encode(to: encoder)
    }

    static func == (lhs: MastodonStatusWrapper, rhs: MastodonStatusWrapper) -> Bool {
        lhs.status == rhs.status
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(status)
    }
}

// MARK: - MastodonStatus Convenience Extensions

private let iso8601Formatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601FormatterNoFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

extension MastodonStatus {

    /// Attempts to parse `createdAt` as a `Date` using ISO 8601 formatting.
    /// Returns `nil` when the string cannot be parsed.
    var createdDate: Date? {
        iso8601Formatter.date(from: createdAt)
            ?? iso8601FormatterNoFractional.date(from: createdAt)
    }

    /// `true` when this status is a boost of another status.
    var isReblog: Bool {
        reblog != nil
    }

    /// The canonical status to display — unwraps reblog if present.
    var displayStatus: MastodonStatus {
        reblog?.status ?? self
    }
}
