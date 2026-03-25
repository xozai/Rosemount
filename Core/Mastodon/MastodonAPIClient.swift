// MastodonAPIClient.swift
// Rosemount
//
// Actor-isolated Mastodon REST API v1/v2 client.
// All network calls use async/await with URLSession.shared.
// Swift 5.10 | iOS 17.0+
//
// Types from other files referenced here:
//   MastodonStatus         — Defined in MastodonStatus.swift
//   MastodonAccount        — Defined in MastodonAccount.swift
//   MastodonRelationship   — Defined in MastodonAccount.swift
//   MastodonAttachment     — Defined in MastodonStatus.swift
//   MastodonVisibility     — Defined in MastodonStatus.swift
//   MastodonEmoji          — Defined in MastodonAccount.swift

import Foundation

// MARK: - Supporting API Types

// MARK: MastodonNotificationType

enum MastodonNotificationType: String, Codable {
    case mention        = "mention"
    case status         = "status"
    case reblog         = "reblog"
    case follow         = "follow"
    case followRequest  = "follow_request"
    case favourite      = "favourite"
    case poll           = "poll"
    case update         = "update"
}

// MARK: MastodonNotification

/// A single notification entity returned by the notifications endpoint.
struct MastodonNotification: Codable, Identifiable {
    let id: String
    let type: MastodonNotificationType
    let createdAt: String
    let account: MastodonAccount
    let status: MastodonStatus?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case createdAt = "created_at"
        case account
        case status
    }
}

// MARK: MastodonSearchType

enum MastodonSearchType: String {
    case accounts  = "accounts"
    case statuses  = "statuses"
    case hashtags  = "hashtags"
}

// MARK: MastodonSearchResults

struct MastodonSearchResults: Codable {
    let accounts: [MastodonAccount]
    let statuses: [MastodonStatus]
    // Hashtags are returned as Tag objects; reuse MastodonTag from MastodonStatus.swift
    let hashtags: [MastodonTag]
}

// MARK: MastodonAPIError

/// Server-side error body returned by the Mastodon API.
struct MastodonAPIError: Codable, LocalizedError {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

// MARK: - MastodonClientError

enum MastodonClientError: Error, LocalizedError {
    case invalidURL
    case httpError(statusCode: Int, body: String)
    case decodingError(underlying: Error)
    case unknown(underlying: Error)
    /// HTTP 401 — token invalid or expired; triggers logout.
    case unauthorized
    /// HTTP 5xx — server-side error.
    case serverError(code: Int)
    /// HTTP 429 — rate limited; `retryAfter` seconds until reset.
    case rateLimited(retryAfter: TimeInterval?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not construct a valid request URL."
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodingError(let err):
            return "Response decoding failed: \(err.localizedDescription)"
        case .unknown(let err):
            return err.localizedDescription
        case .unauthorized:
            return "Your session has expired. Please sign in again."
        case .serverError(let code):
            return "The server encountered an error (HTTP \(code)). Please try again later."
        case .rateLimited(let retry):
            if let retry {
                return "You're doing that too fast. Please wait \(Int(retry)) seconds."
            }
            return "You're doing that too fast. Please try again later."
        }
    }
}

// MARK: - MastodonAPIClient

/// Actor-isolated client for the Mastodon REST API.
///
/// All methods are `async throws`. The actor guarantees that the mutable
/// `instanceURL` and `accessToken` properties are only accessed from within
/// the actor's executor.
actor MastodonAPIClient {

    // MARK: - Properties

    private let instanceURL: URL
    private let accessToken: String

    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: - Init

    init(instanceURL: URL, accessToken: String, session: URLSession = .shared) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
        self.session = session

        let d = JSONDecoder()
        // Use .convertFromSnakeCase so we don't need CodingKeys in every model.
        // Models that need precise key control override via their own CodingKeys.
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        self.decoder = d
    }

    // MARK: - Timeline

    /// Returns the home timeline (accounts the authenticated user follows).
    func homeTimeline(
        maxId: String? = nil,
        sinceId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonStatus] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId   { items.append(URLQueryItem(name: "max_id",   value: maxId)) }
        if let sinceId { items.append(URLQueryItem(name: "since_id", value: sinceId)) }
        return try await request("/api/v1/timelines/home", queryItems: items)
    }

    /// Returns the local (instance) public timeline.
    func localTimeline(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonStatus] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "local", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await request("/api/v1/timelines/public", queryItems: items)
    }

    /// Returns the federated (global) public timeline.
    func federatedTimeline(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonStatus] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await request("/api/v1/timelines/public", queryItems: items)
    }

    // MARK: - Statuses

    /// Creates and publishes a new status.
    func createStatus(
        content: String,
        visibility: MastodonVisibility = .public,
        inReplyToId: String? = nil,
        spoilerText: String? = nil,
        sensitive: Bool = false,
        mediaIds: [String] = []
    ) async throws -> MastodonStatus {
        var body: [String: Any] = [
            "status":     content,
            "visibility": visibility.rawValue,
            "sensitive":  sensitive,
        ]
        if let inReplyToId { body["in_reply_to_id"] = inReplyToId }
        if let spoilerText, !spoilerText.isEmpty { body["spoiler_text"] = spoilerText }
        if !mediaIds.isEmpty { body["media_ids"] = mediaIds }

        return try await request("/api/v1/statuses", method: "POST", body: body)
    }

    /// Deletes a status authored by the authenticated user.
    func deleteStatus(id: String) async throws {
        let _: EmptyResponse = try await request("/api/v1/statuses/\(id)", method: "DELETE")
    }

    /// Boosts (reblogs) the given status.
    func boostStatus(id: String) async throws -> MastodonStatus {
        try await request("/api/v1/statuses/\(id)/reblog", method: "POST")
    }

    /// Removes a boost on the given status.
    func unboostStatus(id: String) async throws -> MastodonStatus {
        try await request("/api/v1/statuses/\(id)/unreblog", method: "POST")
    }

    /// Favourites (likes) the given status.
    func favouriteStatus(id: String) async throws -> MastodonStatus {
        try await request("/api/v1/statuses/\(id)/favourite", method: "POST")
    }

    /// Removes a favourite from the given status.
    func unfavouriteStatus(id: String) async throws -> MastodonStatus {
        try await request("/api/v1/statuses/\(id)/unfavourite", method: "POST")
    }

    /// Bookmarks the given status for the authenticated user.
    func bookmarkStatus(id: String) async throws -> MastodonStatus {
        try await request("/api/v1/statuses/\(id)/bookmark", method: "POST")
    }

    // MARK: - Accounts

    /// Verifies that the access token is valid and returns the authenticated account.
    func verifyCredentials() async throws -> MastodonAccount {
        try await request("/api/v1/accounts/verify_credentials")
    }

    /// Fetches a single account by ID.
    func account(id: String) async throws -> MastodonAccount {
        try await request("/api/v1/accounts/\(id)")
    }

    /// Follows the account with the given ID.
    func follow(id: String) async throws -> MastodonRelationship {
        try await request("/api/v1/accounts/\(id)/follow", method: "POST")
    }

    /// Unfollows the account with the given ID.
    func unfollow(id: String) async throws -> MastodonRelationship {
        try await request("/api/v1/accounts/\(id)/unfollow", method: "POST")
    }

    /// Blocks the account with the given ID.
    func block(id: String) async throws -> MastodonRelationship {
        try await request("/api/v1/accounts/\(id)/block", method: "POST")
    }

    /// Mutes the account with the given ID.
    func mute(id: String) async throws -> MastodonRelationship {
        try await request("/api/v1/accounts/\(id)/mute", method: "POST")
    }

    /// Returns the relationships between the authenticated user and the given account IDs.
    func relationships(ids: [String]) async throws -> [MastodonRelationship] {
        let items = ids.map { URLQueryItem(name: "id[]", value: $0) }
        return try await request("/api/v1/accounts/relationships", queryItems: items)
    }

    // MARK: - Notifications

    /// Returns notifications for the authenticated user.
    func notifications(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonNotification] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await request("/api/v1/notifications", queryItems: items)
    }

    // MARK: - Search

    /// Performs a full-text search across accounts, statuses, and hashtags.
    func search(
        query: String,
        type: MastodonSearchType? = nil,
        limit: Int = 20
    ) async throws -> MastodonSearchResults {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "q",     value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let type { items.append(URLQueryItem(name: "type", value: type.rawValue)) }
        return try await request("/api/v2/search", queryItems: items)
    }

    // MARK: - Media

    /// Uploads media data and returns the resulting attachment entity.
    func uploadMedia(
        data: Data,
        mimeType: String,
        description: String? = nil
    ) async throws -> MastodonAttachment {
        let boundary = "RosemountBoundary-\(UUID().uuidString)"
        let url = buildURL("/api/v2/media", queryItems: [])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // File part
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"upload\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(data)
        body.append("\r\n".utf8Data)

        // Optional description part
        if let description {
            body.append("--\(boundary)\r\n".utf8Data)
            body.append("Content-Disposition: form-data; name=\"description\"\r\n\r\n".utf8Data)
            body.append(description.utf8Data)
            body.append("\r\n".utf8Data)
        }

        body.append("--\(boundary)--\r\n".utf8Data)
        request.httpBody = body

        let (responseData, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: responseData)

        do {
            return try decoder.decode(MastodonAttachment.self, from: responseData)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    // MARK: - Private Helpers

    /// Generic GET request helper. Builds a URL, attaches the Bearer token, and decodes.
    private func request<T: Decodable>(
        _ endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(endpoint, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Generic POST/DELETE request helper with an optional JSON body.
    private func request<T: Decodable>(
        _ endpoint: String,
        method: String,
        body: [String: Any]? = nil,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(endpoint, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Constructs a full URL by appending `path` to `instanceURL` and attaching query items.
    private func buildURL(_ path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: instanceURL.appendingPathComponent(path.hasPrefix("/") ? String(path.dropFirst()) : path),
            resolvingAgainstBaseURL: false
        )!
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        return components.url!
    }

    /// Throws a typed `MastodonClientError` for non-2xx responses.
    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200...299).contains(http.statusCode) else { return }
        switch http.statusCode {
        case 401:
            throw MastodonClientError.unauthorized
        case 429:
            let retryAfterHeader = http.value(forHTTPHeaderField: "Retry-After")
            let retryAfter = retryAfterHeader.flatMap(TimeInterval.init)
            throw MastodonClientError.rateLimited(retryAfter: retryAfter)
        case 500...599:
            throw MastodonClientError.serverError(code: http.statusCode)
        default:
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

// MARK: - EmptyResponse

/// Placeholder decodable used for endpoints that return an empty body (e.g. DELETE).
private struct EmptyResponse: Decodable {}

// MARK: - Data + UTF8 Helpers

private extension String {
    var utf8Data: Data { Data(utf8) }
}
