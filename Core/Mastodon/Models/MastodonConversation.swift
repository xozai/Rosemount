// MastodonConversation.swift
// Rosemount
//
// Mastodon direct-message conversation model matching the
// GET /api/v1/conversations response schema.
// Reference: https://docs.joinmastodon.org/entities/Conversation/
// Swift 5.10 | iOS 17.0+

import Foundation

// MastodonAccount — defined in MastodonAccount.swift
// MastodonStatus  — defined in MastodonStatus.swift

// MARK: - MastodonConversation

/// A direct-message conversation thread between the authenticated user
/// and one or more other participants.
struct MastodonConversation: Codable, Identifiable, Hashable {

    // MARK: Properties

    /// Unique ID for this conversation.
    let id: String

    /// Whether the authenticated user has unread messages in this conversation.
    let unread: Bool

    /// The other participants in this conversation (excludes the authenticated user).
    let accounts: [MastodonAccount]

    /// The most recent status in the conversation, if any.
    let lastStatus: MastodonStatus?

    // MARK: CodingKeys

    enum CodingKeys: String, CodingKey {
        case id
        case unread
        case accounts
        case lastStatus = "last_status"
    }

    // MARK: Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: MastodonConversation, rhs: MastodonConversation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - MastodonConversation Convenience Extensions

extension MastodonConversation {

    /// Returns the first participant, which is the primary "other" account in a two-person DM.
    /// For group conversations, use `accounts` directly.
    var otherParticipant: MastodonAccount? {
        accounts.first
    }

    /// A human-readable title for the conversation made up of participants' display names.
    /// Falls back to `username` when `displayName` is empty.
    var displayTitle: String {
        let names = accounts.map { account in
            account.displayName.isEmpty ? account.username : account.displayName
        }
        guard !names.isEmpty else { return "Conversation" }
        return names.joined(separator: ", ")
    }
}

// MARK: - MastodonConversationDraft

/// Transient struct used to compose a new direct-message conversation.
/// Not Codable — only used locally in the compose UI.
struct MastodonConversationDraft {

    /// The full Mastodon handle of the intended recipient, e.g. `@alice@mastodon.social`.
    var recipientHandle: String

    /// The text body of the first message to send.
    var content: String

    // MARK: Init

    init(recipientHandle: String = "", content: String = "") {
        self.recipientHandle = recipientHandle
        self.content = content
    }

    // MARK: Helpers

    /// Returns true when both fields are non-empty and a send can be attempted.
    var isValid: Bool {
        !recipientHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Builds the full status text — prepends the @mention if not already present.
    func statusText() -> String {
        let handle = recipientHandle.hasPrefix("@") ? recipientHandle : "@\(recipientHandle)"
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix(handle) else { return trimmed }
        return "\(handle) \(trimmed)"
    }
}
