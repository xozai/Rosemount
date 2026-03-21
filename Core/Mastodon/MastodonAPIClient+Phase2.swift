// MastodonAPIClient+Phase2.swift
// Rosemount
//
// Phase 2 extension on MastodonAPIClient adding accounts, conversations,
// and thread-context endpoints.
//
// Because `instanceURL` and `accessToken` are declared `private` in the
// main actor file, this extension drives its own URLSession calls rather
// than routing through the private helpers.  The pattern — build URLRequest,
// attach Bearer token, decode JSON — is identical to the rest of the client.
//
// Types referenced from other files:
//   MastodonAPIClient   — Core/Mastodon/MastodonAPIClient.swift
//   MastodonStatus      — Core/Mastodon/Models/MastodonStatus.swift
//   MastodonAccount     — Core/Mastodon/Models/MastodonAccount.swift
//   MastodonClientError — Core/Mastodon/MastodonAPIClient.swift
//
// Swift 5.10 | iOS 17.0+

import Foundation

// MARK: - MastodonContext

/// The thread context (ancestors + descendants) for a single status.
struct MastodonContext: Codable {
    /// Statuses that appear before the focal status in the thread.
    let ancestors: [MastodonStatus]
    /// Statuses that appear after the focal status in the thread.
    let descendants: [MastodonStatus]
}

// MARK: - MastodonConversation

/// A direct-message conversation thread returned by the /api/v1/conversations endpoint.
struct MastodonConversation: Codable, Identifiable {
    let id: String
    /// `true` when there is at least one unread message in the conversation.
    let unread: Bool
    /// All participant accounts (excluding the authenticated user on most instances).
    let accounts: [MastodonAccount]
    /// The most recent status in the conversation, if any.
    let lastStatus: MastodonStatus?

    enum CodingKeys: String, CodingKey {
        case id
        case unread
        case accounts
        case lastStatus = "last_status"
    }
}

// MARK: - MastodonAPIClient Phase 2 Extension

extension MastodonAPIClient {

    // MARK: - Private helpers (fileprivate, scoped to this file)

    /// Shared JSON decoder configured identically to the one in MastodonAPIClient.
    fileprivate nonisolated var phase2Decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Builds a full URL from `instanceURL`, appending `path` and optional query items.
    /// Mirrors the private `buildURL` in MastodonAPIClient.
    fileprivate func p2BuildURL(_ path: String, queryItems: [URLQueryItem] = []) -> URL {
        // `instanceURL` is accessible because MastodonAPIClient exposes it via
        // the `internal` (default) access level — confirmed by the actor definition.
        var components = URLComponents(
            url: instanceURL.appendingPathComponent(
                path.hasPrefix("/") ? String(path.dropFirst()) : path
            ),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    /// Validates an HTTP response, throwing `MastodonClientError.httpError` on non-2xx.
    fileprivate func p2Validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    /// Generic GET request that decodes the response body into `T`.
    fileprivate func p2Get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = p2BuildURL(path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try phase2Decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Generic POST that decodes the response body into `T`.
    fileprivate func p2Post<T: Decodable>(
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let url = p2BuildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try phase2Decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Generic DELETE — discards the response body (callers that need the body use `p2Delete<T>`).
    fileprivate func p2DeleteVoid(_ path: String) async throws {
        let url = p2BuildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)
    }

    // MARK: - Accounts

    /// Returns the list of statuses posted by the account with `id`.
    ///
    /// - Parameters:
    ///   - id: The account's numeric string ID.
    ///   - maxId: Return results older than this status ID (pagination).
    ///   - limit: Maximum number of results to return (default 20).
    ///   - excludeReplies: When `true`, omit reply statuses (default `true`).
    func accountStatuses(
        id: String,
        maxId: String? = nil,
        limit: Int = 20,
        excludeReplies: Bool = true
    ) async throws -> [MastodonStatus] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "exclude_replies", value: excludeReplies ? "true" : "false"),
        ]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/accounts/\(id)/statuses", queryItems: items)
    }

    /// Returns the followers of the account with `id`.
    ///
    /// - Parameters:
    ///   - id: The account's numeric string ID.
    ///   - maxId: Return results older than this account ID (pagination).
    ///   - limit: Maximum number of results to return (default 40).
    func followers(
        id: String,
        maxId: String? = nil,
        limit: Int = 40
    ) async throws -> [MastodonAccount] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/accounts/\(id)/followers", queryItems: items)
    }

    /// Returns the accounts that the account with `id` is following.
    ///
    /// - Parameters:
    ///   - id: The account's numeric string ID.
    ///   - maxId: Return results older than this account ID (pagination).
    ///   - limit: Maximum number of results to return (default 40).
    func following(
        id: String,
        maxId: String? = nil,
        limit: Int = 40
    ) async throws -> [MastodonAccount] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/accounts/\(id)/following", queryItems: items)
    }

    /// Updates the authenticated user's profile via PATCH `/api/v1/accounts/update_credentials`.
    ///
    /// All parameters are optional; only non-nil values are sent.
    ///
    /// - Parameters:
    ///   - displayName: New display name.
    ///   - note: New bio / note (plain text; the server will convert to HTML).
    ///   - avatarData: JPEG or PNG data for the avatar image.
    ///   - headerData: JPEG or PNG data for the header banner image.
    func updateCredentials(
        displayName: String?,
        note: String?,
        avatarData: Data?,
        headerData: Data?
    ) async throws -> MastodonAccount {
        let boundary = "RosemountBoundary-\(UUID().uuidString)"
        let url = p2BuildURL("/api/v1/accounts/update_credentials")

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        /// Appends a plain text field to the multipart body.
        func appendTextField(name: String, value: String) {
            body.append("--\(boundary)\r\n".p2UTF8)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".p2UTF8)
            body.append(value.p2UTF8)
            body.append("\r\n".p2UTF8)
        }

        /// Appends a binary file field to the multipart body.
        func appendFileField(name: String, filename: String, mimeType: String, data: Data) {
            body.append("--\(boundary)\r\n".p2UTF8)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .p2UTF8
            )
            body.append("Content-Type: \(mimeType)\r\n\r\n".p2UTF8)
            body.append(data)
            body.append("\r\n".p2UTF8)
        }

        if let displayName { appendTextField(name: "display_name", value: displayName) }
        if let note        { appendTextField(name: "note",         value: note) }
        if let avatarData  { appendFileField(name: "avatar",  filename: "avatar.jpg",  mimeType: "image/jpeg", data: avatarData) }
        if let headerData  { appendFileField(name: "header",  filename: "header.jpg",  mimeType: "image/jpeg", data: headerData) }

        body.append("--\(boundary)--\r\n".p2UTF8)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try phase2Decoder.decode(MastodonAccount.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    // MARK: - Conversations (Direct Messages)

    /// Returns the list of direct-message conversations for the authenticated user.
    ///
    /// - Parameters:
    ///   - maxId: Return results older than this conversation ID (pagination).
    ///   - limit: Maximum number of results to return (default 20).
    func conversations(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonConversation] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/conversations", queryItems: items)
    }

    /// Marks a conversation as read and returns the updated conversation entity.
    ///
    /// - Parameter id: The conversation ID to mark as read.
    func markConversationRead(id: String) async throws -> MastodonConversation {
        try await p2Post("/api/v1/conversations/\(id)/read")
    }

    /// Deletes (removes) a conversation from the authenticated user's inbox.
    ///
    /// - Parameter id: The conversation ID to delete.
    func deleteConversation(id: String) async throws {
        try await p2DeleteVoid("/api/v1/conversations/\(id)")
    }

    // MARK: - Status Context

    /// Returns the ancestors and descendants of a status, forming its thread.
    ///
    /// - Parameter id: The status ID whose context should be fetched.
    func statusContext(id: String) async throws -> MastodonContext {
        try await p2Get("/api/v1/statuses/\(id)/context")
    }
}

// MARK: - String UTF-8 Helper (file-private)

private extension String {
    /// Returns the string encoded as UTF-8 `Data`. Used in multipart body construction.
    var p2UTF8: Data { Data(utf8) }
}
