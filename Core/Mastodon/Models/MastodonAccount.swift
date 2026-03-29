// MastodonAccount.swift
// Rosemount
//
// Mastodon Account model matching the Mastodon REST API v1/v2 response schema.
// Reference: https://docs.joinmastodon.org/entities/Account/
// Swift 5.10 | iOS 17.0+

import Foundation

// MARK: - MastodonEmoji

/// A custom emoji used in display names, bio, or field values.
struct MastodonEmoji: Codable, Hashable {
    let shortcode: String
    let url: String
    let staticUrl: String
    let visibleInPicker: Bool

    enum CodingKeys: String, CodingKey {
        case shortcode
        case url
        case staticUrl        = "static_url"
        case visibleInPicker  = "visible_in_picker"
    }
}

// MARK: - MastodonField

/// A profile metadata field (name / value pair) with optional identity proof.
struct MastodonField: Codable, Hashable {
    let name: String
    let value: String
    /// ISO 8601 timestamp string, present when the field has been verified.
    let verifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case name
        case value
        case verifiedAt = "verified_at"
    }
}

// MARK: - MastodonAccount

/// A Mastodon user account entity.
struct MastodonAccount: Codable, Identifiable, Hashable {

    // MARK: Required Fields

    let id: String
    let username: String
    /// `username` for local accounts; `username@domain` for remote accounts.
    let acct: String
    let displayName: String
    let locked: Bool
    let bot: Bool
    /// ISO 8601 date string representing account creation time.
    let createdAt: String
    /// HTML-formatted biography string.
    let note: String
    /// URL of the account's profile page.
    let url: String
    let avatar: String
    let avatarStatic: String
    let header: String
    let headerStatic: String
    let followersCount: Int
    let followingCount: Int
    let statusesCount: Int
    let emojis: [MastodonEmoji]
    let fields: [MastodonField]

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case acct
        case displayName      = "display_name"
        case locked
        case bot
        case createdAt        = "created_at"
        case note
        case url
        case avatar
        case avatarStatic     = "avatar_static"
        case header
        case headerStatic     = "header_static"
        case followersCount   = "followers_count"
        case followingCount   = "following_count"
        case statusesCount    = "statuses_count"
        case emojis
        case fields
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MastodonAccount, rhs: MastodonAccount) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - MastodonAccount Convenience Extensions

extension MastodonAccount {

    /// Returns the full Mastodon handle including the leading `@`.
    /// e.g. `@alice@mastodon.social`
    var fullHandle: String {
        "@\(acct)"
    }

    /// Resolves `avatar` as a `URL`. Returns `nil` when the string is malformed.
    var avatarURL: URL? {
        URL(string: avatar)
    }

    /// Resolves `avatarStatic` as a `URL`. Returns `nil` when the string is malformed.
    var avatarStaticURL: URL? {
        URL(string: avatarStatic)
    }

    /// Resolves `header` as a `URL`. Returns `nil` when the string is malformed.
    var headerURL: URL? {
        URL(string: header)
    }

    /// Resolves `headerStatic` as a `URL`. Returns `nil` when the string is malformed.
    var headerStaticURL: URL? {
        URL(string: headerStatic)
    }

    /// Resolves the profile page `url` as a `URL`. Returns `nil` when malformed.
    var profileURL: URL? {
        URL(string: url)
    }
}

// MARK: - MastodonRelationship

/// The relationship between the authenticated account and another account.
struct MastodonRelationship: Codable, Identifiable {
    let id: String
    let following: Bool
    let showingReblogs: Bool
    let notifying: Bool
    let followedBy: Bool
    let blocking: Bool
    let blockedBy: Bool
    let muting: Bool
    let mutingNotifications: Bool
    let requested: Bool
    let domainBlocking: Bool
    let endorsed: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case following
        case showingReblogs       = "showing_reblogs"
        case notifying
        case followedBy           = "followed_by"
        case blocking
        case blockedBy            = "blocked_by"
        case muting
        case mutingNotifications  = "muting_notifications"
        case requested
        case domainBlocking       = "domain_blocking"
        case endorsed
    }
}
