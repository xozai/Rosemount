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

// MARK: - ConversationsViewModel

/// Observable view-model for the direct-messaging conversations list.
///
/// Responsibilities:
/// - Fetches conversations from the Mastodon conversations endpoint.
/// - Marks individual conversations as read (optimistic + server-side).
/// - Deletes conversations with swipe-to-delete (optimistic removal).
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
            let fetched = try await client.conversations(limit: 40)
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

        // Optimistic update — flip unread to false without waiting for the server.
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
            // Reconcile local list with the server-returned object.
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = serverUpdated
            }
        } catch {
            // Roll back the optimistic update on failure.
            if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
                conversations[index] = conversation
            }
            self.error = error
        }
    }

    // MARK: - Delete

    /// Removes a conversation from the local list immediately, then deletes it on the server.
    func deleteConversation(_ conversation: MastodonConversation) async {
        guard let client else { return }

        // Optimistic removal.
        conversations.removeAll { $0.id == conversation.id }

        do {
            try await client.deleteConversation(id: conversation.id)
        } catch {
            // Re-insert on failure (position is approximate; prepend to keep it visible).
            conversations.insert(conversation, at: 0)
            self.error = error
        }
    }

    // MARK: - List onDelete Helper

    /// Handles deletion from a SwiftUI `List`'s `.onDelete` modifier.
    func deleteConversations(at offsets: IndexSet) {
        let toDelete = offsets.map { conversations[$0] }
        Task {
            for conversation in toDelete {
                await deleteConversation(conversation)
            }
        }
    }
}
