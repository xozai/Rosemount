// Core/ActivityPub/Models/APEmojiReact.swift
// ActivityPub EmojiReact extension (Misskey/Pleroma compatible)

import Foundation

// MARK: - AP Emoji React

struct APEmojiReact: Codable {
    var id: String
    var type: String = "EmojiReact"
    var actor: String
    var object: String
    var content: String
    var tag: [APEmojiTag]?
    var to: [String]
    var cc: [String]
}

struct APEmojiTag: Codable {
    var type: String       // "Emoji"
    var name: String?      // ":shortcode:" for custom
    var icon: APEmojiIcon?
}

struct APEmojiIcon: Codable {
    var type: String       // "Image"
    var url: String
}

// MARK: - Reaction Summary

struct ReactionSummary: Codable, Identifiable {
    var emoji: String
    var count: Int
    var hasReacted: Bool
    var accounts: [String]

    var id: String { emoji }

    enum CodingKeys: String, CodingKey {
        case emoji, count, accounts
        case hasReacted = "me"
    }

    init(emoji: String, count: Int, hasReacted: Bool, accounts: [String] = []) {
        self.emoji = emoji
        self.count = count
        self.hasReacted = hasReacted
        self.accounts = accounts
    }
}

// MARK: - MastodonStatus Reactions Extension
// Note: Mastodon-Glitch/Pleroma include a non-standard "reactions" field.
// Parsed via a custom decoder extension in MastodonStatus+Reactions.swift.
// For compile-time reference only — actual parsing happens in the API layer.
