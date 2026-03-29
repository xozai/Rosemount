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

// MARK: - MastodonAPIClient Conversation Stubs
//
// NOTE: Add these methods to MastodonAPIClient in MastodonAPIClient.swift
// func conversations(maxId: String?, limit: Int) async throws -> [MastodonConversation]
//   GET /api/v1/conversations
// func markConversationRead(id: String) async throws -> MastodonConversation
//   POST /api/v1/conversations/:id/read
// func deleteConversation(id: String) async throws
//   DELETE /api/v1/conversations/:id

// MARK: - ConversationAPIClient
//
// A thin, self-contained async helper for conversation endpoints.
// Mirrors the conventions of MastodonAPIClient without requiring access to its
// private stored properties. Intended to be replaced once the stub methods above
// are added to MastodonAPIClient.swift.

private struct ConversationAPIClient {

    let instanceURL: URL
    let accessToken: String

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: Endpoints

    /// GET /api/v1/conversations
    func conversations(maxId: String? = nil, limit: Int = 40) async throws -> [MastodonConversation] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await get("/api/v1/conversations", queryItems: items)
    }

    /// POST /api/v1/conversations/:id/read
    func markConversationRead(id: String) async throws -> MastodonConversation {
        try await post("/api/v1/conversations/\(id)/read")
    }

    /// DELETE /api/v1/conversations/:id
    func deleteConversation(id: String) async throws {
        let _: EmptyConversationBody = try await delete("/api/v1/conversations/\(id)")
    }

    // MARK: Private helpers

    private func get<T: Decodable>(_ path: String, queryItems: [URLQueryItem] = []) async throws -> T {
        let url = buildURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func post<T: Decodable>(_ path: String) async throws -> T {
        let url = buildURL(path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func delete<T: Decodable>(_ path: String) async throws -> T {
        let url = buildURL(path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await perform(request)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }
        do {
            // Return empty data as an empty object for DELETE responses.
            let safeData = data.isEmpty ? Data("{}".utf8) : data
            return try decoder.decode(T.self, from: safeData)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    private func buildURL(_ path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = path
        if !queryItems.isEmpty { components.queryItems = queryItems }
        return components.url!
    }
}

/// Placeholder for DELETE responses that return an empty body or `{}`.
private struct EmptyConversationBody: Decodable {}

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

    /// Retained for any operations that go through MastodonAPIClient (e.g. createStatus).
    private var client: MastodonAPIClient?

    /// Thin helper for the conversation-specific endpoints.
    private var conversationClient: ConversationAPIClient?

    // MARK: - Setup

    /// Configures both API helpers from the provided credential.
    /// Must be called before any data-loading methods.
    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
        conversationClient = ConversationAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Data Loading

    /// Fetches the full conversations list, replacing any existing data.
    /// Also clears the app badge as a side effect of opening the messages tab.
    func refresh() async {
        guard let conversationClient else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            let fetched = try await conversationClient.conversations(limit: 40)
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
        guard let conversationClient else { return }
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
            let serverUpdated = try await conversationClient.markConversationRead(id: conversation.id)
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
        guard let conversationClient else { return }

        // Optimistic removal.
        conversations.removeAll { $0.id == conversation.id }

        do {
            try await conversationClient.deleteConversation(id: conversation.id)
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
