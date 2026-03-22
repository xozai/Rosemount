// Core/Offline/DraftPost.swift
// SwiftData model for draft posts
//
// CachedStatus  — defined in Shared/SwiftData/CachedStatus.swift
// PendingAction — defined below; used only by OfflineStore / BackgroundSyncService

import Foundation
import SwiftData

@Model
final class DraftPost {
    var id: UUID
    var content: String
    var visibility: String        // MastodonVisibility rawValue
    var attachmentURLs: [String]  // local file URLs for media
    var communitySlug: String?
    var replyToId: String?
    var pollOptionsJSON: String?   // JSON-encoded poll payload
    var createdAt: Date
    var updatedAt: Date

    init(
        content: String,
        visibility: String = "public",
        attachmentURLs: [String] = [],
        communitySlug: String? = nil,
        replyToId: String? = nil,
        pollOptionsJSON: String? = nil
    ) {
        self.id = UUID()
        self.content = content
        self.visibility = visibility
        self.attachmentURLs = attachmentURLs
        self.communitySlug = communitySlug
        self.replyToId = replyToId
        self.pollOptionsJSON = pollOptionsJSON
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var visibilityEnum: MastodonVisibility {
        MastodonVisibility(rawValue: visibility) ?? .public
    }
}

// MARK: - Pending Action (actions queued while offline)

@Model
final class PendingAction {
    var id: UUID
    var type: String         // "favourite", "boost", "reply", "follow"
    var targetId: String
    var payload: String?     // JSON for reply content etc.
    var createdAt: Date
    var retryCount: Int

    init(type: String, targetId: String, payload: String? = nil) {
        self.id = UUID()
        self.type = type
        self.targetId = targetId
        self.payload = payload
        self.createdAt = Date()
        self.retryCount = 0
    }
}
