// ConversationsViewModel.swift
// Rosemount
//
// Observable view-model backing the DM conversations list.
// Handles fetching, marking-as-read, and deleting conversations.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MastodonAPIClient      — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonConversation   — defined in Core/Mastodon/Models/MastodonConversation.swift
// AccountCredential      — defined in Core/Auth/AuthManager.swift
// PushNotificationService — defined in Core/Notifications/PushNotificationService.swift

// MARK: - MastodonAPIClient Conversation Extension
//
// NOTE: Add these to MastodonAPIClient in MastodonAPIClient.swift
// func conversations(maxId: String?, limit: Int) async throws -> [MastodonConversation]
//   GET /api/v1/conversations
// func markConversationRead(id: String) async throws -> MastodonConversation
//   POST /api/v1/conversations/:id/read
// func deleteConversation(id: String) async throws
//   DELETE /api/v1/conversations/:id

// MARK: - ConversationsViewModel

/// Observable view-model for the direct-messaging conversations list.
///
/// Responsibilities:
/// - Fetches conversations from `MastodonAPIClient`.
/// - Marks individual conversations as read (optimistic + server-side).
/// - Deletes conversations with swipe-to-delete.
/// - Clears the unread badge when the list is refreshed.
@Observable
@MainActor
final class ConversationsViewModel {

    // MARK: - Observable State

    /// All conversations for the authenticated user, sorted newest-first.
    var conversations: [MastodonConversation] = []

    /// `true` while a fetch is in flight.
    var isLoading: Bool = false

    /// Non-nil when the most recent operation failed.
    var error: Error?

    // MARK: - Private State

    private var client: MastodonAPIClient?

    // MARK: - Setup

    /// Configures the API client from the provided credential.
    /// Must be called before any data-loading methods.
    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Data Loading

    /// Fetches the full conversations list, replacing any existing data.
    /// Also clears the app badge as a side effect of opening the messages tab.
    func refresh() async {
        guard let client else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let fetched = try await client.conversations(maxId: nil, limit: 40)
            conversations = fetched
            // Clear unread badge when the user opens the conversations list.
            await PushNotificationService.shared.clearBadge()
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Read State

    /// Marks a conversation as read, both optimistically in the local list and
    /// via the server API.
    func markRead(conversation: MastodonConversation) async {
        guard let client else { return }
        guard conversation.unread else { return }

        // Optimistic update: mark unread=false locally without waiting for the server.
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            let updated = MastodonConversation(
                id: conversation.id,
                unread: false,
                accounts: conversation.accounts,
                lastStatus: conversation.lastStatus
            )
            conversations[index] = updated
        }

        do {
            let serverUpdated = try await client.markConversationRead(id: conversation.id)
            // Reconcile with the server-returned object.
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = serverUpdated
            }
        } catch {
            // Roll back optimistic update on failure.
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversation
            }
            self.error = error
        }
    }

    // MARK: - Delete

    /// Deletes a conversation both from the local list (immediately) and from the server.
    func deleteConversation(_ conversation: MastodonConversation) async {
        guard let client else { return }

        // Optimistic removal.
        conversations.removeAll { $0.id == conversation.id }

        do {
            try await client.deleteConversation(id: conversation.id)
        } catch {
            // Re-insert on failure (at the beginning; exact position is lost).
            conversations.insert(conversation, at: 0)
            self.error = error
        }
    }

    // MARK: - Deletion Index Set Helper (for List onDelete)

    /// Deletes conversations at the provided index set from the list.
    /// Intended for use with `List`'s `.onDelete` modifier.
    func deleteConversations(at offsets: IndexSet) {
        let toDelete = offsets.map { conversations[$0] }
        Task {
            for conversation in toDelete {
                await deleteConversation(conversation)
            }
        }
    }
}
