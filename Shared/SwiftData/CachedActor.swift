// CachedActor.swift
// Rosemount
//
// SwiftData model for caching ActivityPub actors / Mastodon accounts locally.
// Mirrors the essential fields of MastodonAccount (defined in Core/Mastodon/Models/MastodonAccount.swift)
// in a persistable, query-friendly form.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import SwiftData

// MARK: - CachedActor

// MastodonAccount — defined in Core/Mastodon/Models/MastodonAccount.swift
// FederationPlatform — defined in Core/Auth/AuthManager.swift

@Model
final class CachedActor {

    // MARK: Identity

    /// The canonical actor URL (ActivityPub) or Mastodon account ID.
    /// Unique per stored actor.
    @Attribute(.unique) var id: String

    /// Full handle in `@user@instance` form, e.g. `@alice@mastodon.social`.
    var handle: String

    var displayName: String

    // MARK: Profile Content

    /// HTML-formatted biography string; `nil` when not available.
    var bio: String?

    /// Remote URL string for the actor's avatar image.
    var avatarURL: String?

    /// Remote URL string for the actor's header/banner image.
    var headerURL: String?

    /// The hostname of the instance this actor belongs to (e.g. `mastodon.social`).
    var instanceHost: String

    /// The platform this actor was fetched from: "mastodon", "pixelfed", or "rosemount".
    var platform: String

    // MARK: Engagement Counts

    var followersCount: Int
    var followingCount: Int
    var statusesCount: Int

    // MARK: Account Flags

    /// Whether the account requires follow requests to be approved.
    var locked: Bool

    /// Whether the account is a bot / automated account.
    var bot: Bool

    // MARK: ActivityPub

    /// PEM-encoded RSA public key used for HTTP Signature verification; `nil` for cached
    /// accounts where key material is not needed client-side.
    var publicKeyPem: String?

    // MARK: Timestamps

    /// When this cache entry was last refreshed from the network.
    var fetchedAt: Date

    // MARK: Viewer-Relative Relationship State

    /// Whether the currently authenticated user is following this actor.
    var isFollowing: Bool

    /// Whether this actor is following the currently authenticated user.
    var isFollowedBy: Bool

    // MARK: - Init

    init(
        id: String,
        handle: String,
        displayName: String,
        bio: String? = nil,
        avatarURL: String? = nil,
        headerURL: String? = nil,
        instanceHost: String,
        platform: String,
        followersCount: Int = 0,
        followingCount: Int = 0,
        statusesCount: Int = 0,
        locked: Bool = false,
        bot: Bool = false,
        publicKeyPem: String? = nil,
        fetchedAt: Date = Date(),
        isFollowing: Bool = false,
        isFollowedBy: Bool = false
    ) {
        self.id             = id
        self.handle         = handle
        self.displayName    = displayName
        self.bio            = bio
        self.avatarURL      = avatarURL
        self.headerURL      = headerURL
        self.instanceHost   = instanceHost
        self.platform       = platform
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.statusesCount  = statusesCount
        self.locked         = locked
        self.bot            = bot
        self.publicKeyPem   = publicKeyPem
        self.fetchedAt      = fetchedAt
        self.isFollowing    = isFollowing
        self.isFollowedBy   = isFollowedBy
    }
}

// MARK: - Factory

extension CachedActor {

    /// Creates a `CachedActor` from a live `MastodonAccount` network response.
    ///
    /// - Parameters:
    ///   - account: The source network model.
    ///             `MastodonAccount` is defined in `Core/Mastodon/Models/MastodonAccount.swift`.
    ///   - platform: The federation platform label ("mastodon", "pixelfed", "rosemount").
    ///   - isFollowing: Whether the authenticated user follows this actor (default: `false`).
    ///   - isFollowedBy: Whether this actor follows the authenticated user (default: `false`).
    /// - Returns: A fully populated `CachedActor` ready for insertion into the SwiftData context.
    static func from(
        _ account: MastodonAccount,
        platform: String,
        isFollowing: Bool = false,
        isFollowedBy: Bool = false
    ) -> CachedActor {
        // Derive the instance host from the account URL; fall back to the acct domain component.
        let instanceHost: String = {
            if let url = URL(string: account.url), let host = url.host {
                return host
            }
            // acct is "user@instance" for remote accounts; local accounts have no "@".
            let components = account.acct.split(separator: "@")
            if components.count == 2 {
                return String(components[1])
            }
            return ""
        }()

        return CachedActor(
            id:             account.id,
            handle:         account.acct,
            displayName:    account.displayName,
            bio:            account.note.isEmpty ? nil : account.note,
            avatarURL:      account.avatar.isEmpty ? nil : account.avatar,
            headerURL:      account.header.isEmpty ? nil : account.header,
            instanceHost:   instanceHost,
            platform:       platform,
            followersCount: account.followersCount,
            followingCount: account.followingCount,
            statusesCount:  account.statusesCount,
            locked:         account.locked,
            bot:            account.bot,
            publicKeyPem:   nil, // Not exposed by the Mastodon REST API.
            fetchedAt:      Date(),
            isFollowing:    isFollowing,
            isFollowedBy:   isFollowedBy
        )
    }
}

// MARK: - Convenience

extension CachedActor {

    /// Resolves `avatarURL` as a `URL`. Returns `nil` when absent or malformed.
    var resolvedAvatarURL: URL? {
        avatarURL.flatMap { URL(string: $0) }
    }

    /// Resolves `headerURL` as a `URL`. Returns `nil` when absent or malformed.
    var resolvedHeaderURL: URL? {
        headerURL.flatMap { URL(string: $0) }
    }

    /// Returns the full handle with a leading `@`, e.g. `@alice@mastodon.social`.
    var fullHandle: String {
        handle.hasPrefix("@") ? handle : "@\(handle)"
    }
}
