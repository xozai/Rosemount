// CachedCommunity.swift
// Rosemount
//
// SwiftData model for locally caching RosemountCommunity values between network fetches.

import Foundation
import SwiftData

// MARK: - CachedCommunity

/// A SwiftData-backed, on-device cache entry for a `RosemountCommunity`.
///
/// Network responses are mapped into `CachedCommunity` records so the app can
/// display community data while a refresh is in flight.  Each row is keyed by
/// the community's canonical ActivityPub `id` URL, enforced as unique.
@Model
final class CachedCommunity {

    // MARK: Persistent properties

    /// Canonical ActivityPub ID, e.g. `"https://rosemount.social/communities/softball-league"`.
    /// Marked unique so upsert semantics work correctly via SwiftData's `@Attribute(.unique)`.
    @Attribute(.unique) var id: String

    /// URL-safe community slug, e.g. `"softball-league"`.
    var slug: String

    /// Human-readable display name.
    var name: String

    /// Plain-text description.  Named `communityDescription` to avoid shadowing
    /// the Swift standard-library `description` property.
    var communityDescription: String

    /// Optional URL string for the community avatar image.
    var avatarURL: String?

    /// Optional URL string for the community header / banner image.
    var headerURL: String?

    /// `true` if membership is invite-only.
    var isPrivate: Bool

    /// Cached member count at the time of the last fetch.
    var memberCount: Int

    /// Cached post count at the time of the last fetch.
    var postCount: Int

    /// Raw string representation of the authenticated user's role in this community.
    /// One of `"admin"`, `"moderator"`, `"member"`, or `nil` when not a member.
    var myRoleRaw: String?

    /// `true` if the authenticated user is a member.
    var isMember: Bool

    /// `true` if the authenticated user has pinned this community.
    var isPinned: Bool

    /// Timestamp of the most recent successful fetch from the network.
    var fetchedAt: Date

    /// Timestamp of the most recent post in the community, if known.
    var lastPostAt: Date?

    // MARK: Init

    /// Designated initialiser.  All non-optional properties must be supplied.
    init(
        id: String,
        slug: String,
        name: String,
        communityDescription: String,
        avatarURL: String? = nil,
        headerURL: String? = nil,
        isPrivate: Bool,
        memberCount: Int,
        postCount: Int,
        myRoleRaw: String? = nil,
        isMember: Bool,
        isPinned: Bool,
        fetchedAt: Date = Date(),
        lastPostAt: Date? = nil
    ) {
        self.id = id
        self.slug = slug
        self.name = name
        self.communityDescription = communityDescription
        self.avatarURL = avatarURL
        self.headerURL = headerURL
        self.isPrivate = isPrivate
        self.memberCount = memberCount
        self.postCount = postCount
        self.myRoleRaw = myRoleRaw
        self.isMember = isMember
        self.isPinned = isPinned
        self.fetchedAt = fetchedAt
        self.lastPostAt = lastPostAt
    }

    // MARK: Computed properties

    /// Typed `CommunityRole` derived from the raw string stored in `myRoleRaw`.
    ///
    /// Returns `nil` when `myRoleRaw` is `nil`, empty, or contains an unrecognised value.
    var myRole: CommunityRole? {
        guard let raw = myRoleRaw, !raw.isEmpty else { return nil }
        return CommunityRole(rawValue: raw)
    }

    // MARK: Factory

    /// Creates a new `CachedCommunity` from a freshly decoded `RosemountCommunity`.
    ///
    /// - Parameter community: The network model to persist.
    /// - Returns: A fully populated `CachedCommunity` ready for insertion into a `ModelContext`.
    static func from(_ community: RosemountCommunity) -> CachedCommunity {
        CachedCommunity(
            id: community.id,
            slug: community.slug,
            name: community.name,
            communityDescription: community.description,
            avatarURL: community.avatarURL,
            headerURL: community.headerURL,
            isPrivate: community.isPrivate,
            memberCount: community.memberCount,
            postCount: community.postCount,
            myRoleRaw: community.myRole?.rawValue,
            isMember: community.isMember,
            isPinned: community.isPinned,
            fetchedAt: Date()
        )
    }

    // MARK: Mutating update

    /// Updates all mutable fields in place from a fresher `RosemountCommunity`.
    ///
    /// Call this when a `CachedCommunity` with the same `id` already exists in the
    /// store so you avoid creating a duplicate record.
    ///
    /// - Parameter community: The up-to-date network model.
    func update(from community: RosemountCommunity) {
        slug = community.slug
        name = community.name
        communityDescription = community.description
        avatarURL = community.avatarURL
        headerURL = community.headerURL
        isPrivate = community.isPrivate
        memberCount = community.memberCount
        postCount = community.postCount
        myRoleRaw = community.myRole?.rawValue
        isMember = community.isMember
        isPinned = community.isPinned
        fetchedAt = Date()
    }
}
