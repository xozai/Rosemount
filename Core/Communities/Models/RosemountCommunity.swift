// RosemountCommunity.swift
// Rosemount
//
// Community model — maps to the ActivityPub Group actor + REST metadata.

import Foundation

// MARK: - CommunityRole

/// The role a local user holds within a community.
enum CommunityRole: String, Codable, CaseIterable {
    case admin
    case moderator
    case member

    /// Human-readable label suitable for display in the UI.
    var displayName: String {
        switch self {
        case .admin:      return "Admin"
        case .moderator:  return "Moderator"
        case .member:     return "Member"
        }
    }

    /// SF Symbol name representing this role.
    var systemImage: String {
        switch self {
        case .admin:      return "shield.fill"
        case .moderator:  return "star.fill"
        case .member:     return "person.fill"
        }
    }
}

// MARK: - RosemountCommunity

/// A Rosemount community, corresponding to an ActivityPub `Group` actor plus
/// REST-layer metadata returned by the community-specific API extensions.
struct RosemountCommunity: Codable, Identifiable, Hashable {

    // MARK: Stored properties

    /// Canonical ActivityPub ID, e.g. `"https://rosemount.social/communities/softball-league"`.
    let id: String

    /// URL-safe community slug, e.g. `"softball-league"`.
    let slug: String

    /// Human-readable display name, e.g. `"Springfield Softball League"`.
    let name: String

    /// Plain-text description of the community's purpose.
    let description: String

    /// Optional URL string for the community avatar image.
    let avatarURL: String?

    /// Optional URL string for the community header / banner image.
    let headerURL: String?

    /// `true` if membership is invite-only; `false` if open to anyone.
    let isPrivate: Bool

    /// Total number of members currently in the community.
    let memberCount: Int

    /// Total number of posts ever made in the community.
    let postCount: Int

    /// ISO 8601 creation timestamp, e.g. `"2024-01-15T09:00:00.000Z"`.
    let createdAt: String

    /// Hostname of the instance hosting this community, e.g. `"rosemount.social"`.
    let instanceHost: String

    /// The authenticated user's role in this community, or `nil` if they are not a member.
    let myRole: CommunityRole?

    /// `true` if the authenticated user is currently a member of this community.
    let isMember: Bool

    /// `true` if the authenticated user has pinned this community for quick access.
    let isPinned: Bool

    /// ActivityPub / post IDs of posts that community admins have pinned to the top of the feed.
    let pinnedPostIds: [String]

    // MARK: CodingKeys (snake_case → camelCase)

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case description
        case avatarURL        = "avatar_url"
        case headerURL        = "header_url"
        case isPrivate        = "is_private"
        case memberCount      = "member_count"
        case postCount        = "post_count"
        case createdAt        = "created_at"
        case instanceHost     = "instance_host"
        case myRole           = "my_role"
        case isMember         = "is_member"
        case isPinned         = "is_pinned"
        case pinnedPostIds    = "pinned_post_ids"
    }
}

// MARK: - Convenience extensions

extension RosemountCommunity {

    /// Resolved `URL` for the community avatar, or `nil` if `avatarURL` is absent or malformed.
    var avatarImageURL: URL? {
        URL(string: avatarURL ?? "")
    }

    /// Resolved `URL` for the community header image, or `nil` if `headerURL` is absent or malformed.
    var headerImageURL: URL? {
        URL(string: headerURL ?? "")
    }

    /// Canonical ActivityPub `URL` for this community, derived from `id`.
    var communityURL: URL? {
        URL(string: id)
    }

    /// `true` when the authenticated user's role is `.admin`.
    var isAdmin: Bool {
        myRole == .admin
    }

    /// `true` when the authenticated user is an admin **or** a moderator.
    var isModerator: Bool {
        myRole == .admin || myRole == .moderator
    }
}
