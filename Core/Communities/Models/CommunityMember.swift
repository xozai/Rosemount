// CommunityMember.swift
// Rosemount
//
// Models for community membership, invites, and pinned posts.

import Foundation

// MARK: - CommunityMember

/// Represents a single member of a Rosemount community along with their role
/// and activity metadata returned by the members endpoint.
struct CommunityMember: Codable, Identifiable, Hashable {

    // MARK: Stored properties

    /// Stable identifier — mirrors `account.id`.
    let id: String

    /// The Mastodon account associated with this member.
    let account: MastodonAccount

    /// This member's role within the community.
    let role: CommunityRole

    /// ISO 8601 timestamp recording when the user joined, e.g. `"2024-03-01T12:00:00.000Z"`.
    let joinedAt: String

    /// `true` if the member has posted or otherwise interacted within the last 30 days.
    let isActive: Bool

    // MARK: CodingKeys (snake_case → camelCase)

    enum CodingKeys: String, CodingKey {
        case id
        case account
        case role
        case joinedAt  = "joined_at"
        case isActive  = "is_active"
    }
}

// MARK: - CommunityMember convenience

extension CommunityMember {

    /// Parsed `Date` from the ISO 8601 `joinedAt` string, or `nil` if parsing fails.
    var joinedDate: Date? {
        ISO8601DateFormatter().date(from: joinedAt)
    }
}

// MARK: - CommunityInvite

/// An invite link that can be shared to bring new members into a private (or any) community.
struct CommunityInvite: Codable, Identifiable {

    // MARK: Stored properties

    /// Unique server-assigned identifier for this invite record.
    let id: String

    /// Short alphanumeric invite code, e.g. `"abc123"`.
    let code: String

    /// The `id` of the community this invite grants access to.
    let communityId: String

    /// URL-safe slug of the community this invite is for.
    let communitySlug: String

    /// `handle` of the account that generated this invite.
    let createdByHandle: String

    /// Optional ISO 8601 expiry timestamp. `nil` means the invite never expires.
    let expiresAt: String?

    /// Optional cap on the number of times this invite can be redeemed. `nil` means unlimited.
    let maxUses: Int?

    /// Number of times this invite has already been redeemed.
    let useCount: Int

    /// Full canonical URL for sharing, e.g. `"https://rosemount.social/invite/abc123"`.
    let inviteURL: String

    // MARK: CodingKeys (snake_case → camelCase)

    enum CodingKeys: String, CodingKey {
        case id
        case code
        case communityId      = "community_id"
        case communitySlug    = "community_slug"
        case createdByHandle  = "created_by_handle"
        case expiresAt        = "expires_at"
        case maxUses          = "max_uses"
        case useCount         = "use_count"
        case inviteURL        = "invite_url"
    }
}

// MARK: - CommunityInvite convenience

extension CommunityInvite {

    /// Deep-link `URL` that opens Rosemount directly to the invite acceptance screen.
    var inviteDeepLink: URL? {
        URL(string: "rosemount://invite/\(code)")
    }

    /// `true` if the invite has passed its `expiresAt` timestamp.
    ///
    /// An invite without an expiry date is never considered expired.
    var isExpired: Bool {
        guard let expiresAtString = expiresAt,
              let expiryDate = ISO8601DateFormatter().date(from: expiresAtString) else {
            return false
        }
        return expiryDate < Date()
    }

    /// `true` if the invite has reached its `maxUses` redemption cap.
    ///
    /// An invite without a `maxUses` limit is never considered full.
    var isFull: Bool {
        guard let maxUses else { return false }
        return useCount >= maxUses
    }
}

// MARK: - CommunityPinnedPost

/// A post that a community admin has pinned to the top of the community feed.
struct CommunityPinnedPost: Codable, Identifiable {

    // MARK: Stored properties

    /// Unique identifier for the pin record (not the post itself).
    let id: String

    /// The full `MastodonStatus` that has been pinned.
    let status: MastodonStatus

    /// ISO 8601 timestamp recording when the post was pinned.
    let pinnedAt: String

    /// `handle` of the moderator or admin who pinned the post.
    let pinnedByHandle: String

    // MARK: CodingKeys (snake_case → camelCase)

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case pinnedAt         = "pinned_at"
        case pinnedByHandle   = "pinned_by_handle"
    }
}
