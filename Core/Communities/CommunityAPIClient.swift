// CommunityAPIClient.swift
// Rosemount
//
// REST API client for community-specific endpoints exposed by the Rosemount backend.
// Uses async/await and Foundation's URLSession. No external dependencies.

import Foundation

// MARK: - CommunityAPIError

/// Typed errors surfaced by `CommunityAPIClient`.
enum CommunityAPIError: Error, LocalizedError {
    /// The requested community resource was not found (HTTP 404).
    case notFound
    /// The caller lacks permission for the requested operation (HTTP 403 / 401).
    case forbidden
    /// The server returned an unexpected HTTP error status.
    case serverError(Int)
    /// The response body could not be decoded into the expected type.
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "The requested community could not be found."
        case .forbidden:
            return "You do not have permission to perform this action."
        case .serverError(let code):
            return "The server returned an error (HTTP \(code))."
        case .decodingFailed:
            return "The server response could not be parsed."
        }
    }
}

// MARK: - CommunityAPIClient

/// Actor-isolated REST client for all community-specific Rosemount API endpoints.
///
/// Initialise once per authenticated session and share it across the app.  Because this
/// type is an `actor`, all mutable state (credentials, shared `URLSession`) is protected
/// from data races without additional locking.
actor CommunityAPIClient {

    // MARK: Private state

    private let instanceURL: URL
    private let accessToken: String
    private let session: URLSession
    private let decoder: JSONDecoder

    // MARK: Init

    /// Creates a client bound to a specific instance and OAuth access token.
    ///
    /// - Parameters:
    ///   - instanceURL: Root URL of the Rosemount instance, e.g. `https://rosemount.social`.
    ///   - accessToken: Bearer token obtained during OAuth authorisation.
    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: config)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = dec
    }

    // MARK: - Communities

    /// Returns a paginated list of communities, optionally filtered by a search string.
    ///
    /// `GET /api/v1/communities?search=&page=`
    func discoverCommunities(search: String? = nil, page: Int = 1) async throws -> [RosemountCommunity] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "page", value: String(page))]
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        return try await apiRequest(
            path: "/api/v1/communities",
            method: "GET",
            body: nil,
            contentType: "application/json",
            queryItems: queryItems
        )
    }

    /// Returns all communities the authenticated user has joined.
    ///
    /// `GET /api/v1/communities/joined`
    func myCommunities() async throws -> [RosemountCommunity] {
        return try await apiRequest(
            path: "/api/v1/communities/joined",
            method: "GET",
            body: nil,
            contentType: "application/json"
        )
    }

    /// Fetches a single community by its URL-safe slug.
    ///
    /// `GET /api/v1/communities/:slug`
    func community(slug: String) async throws -> RosemountCommunity {
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)",
            method: "GET",
            body: nil,
            contentType: "application/json"
        )
    }

    /// Creates a new community.  Avatar and header images are sent as multipart data when provided.
    ///
    /// `POST /api/v1/communities (multipart/form-data)`
    func createCommunity(
        name: String,
        description: String,
        isPrivate: Bool,
        avatarData: Data? = nil,
        headerData: Data? = nil
    ) async throws -> RosemountCommunity {
        var fields: [String: String] = [
            "name": name,
            "description": description,
            "is_private": isPrivate ? "true" : "false"
        ]
        _ = fields  // silence potential unused-variable warning if files branch dominates

        var files: [String: (Data, String)] = [:]
        if let avatar = avatarData {
            files["avatar"] = (avatar, "image/jpeg")
        }
        if let header = headerData {
            files["header"] = (header, "image/jpeg")
        }

        return try await multipartRequest(
            path: "/api/v1/communities",
            method: "POST",
            fields: [
                "name": name,
                "description": description,
                "is_private": isPrivate ? "true" : "false"
            ],
            files: files
        )
    }

    /// Updates mutable fields on an existing community.  Pass `nil` to leave a field unchanged.
    ///
    /// `PATCH /api/v1/communities/:slug (multipart/form-data)`
    func updateCommunity(
        slug: String,
        name: String? = nil,
        description: String? = nil,
        isPrivate: Bool? = nil,
        avatarData: Data? = nil,
        headerData: Data? = nil
    ) async throws -> RosemountCommunity {
        var fields: [String: String] = [:]
        if let name { fields["name"] = name }
        if let description { fields["description"] = description }
        if let isPrivate { fields["is_private"] = isPrivate ? "true" : "false" }

        var files: [String: (Data, String)] = [:]
        if let avatar = avatarData { files["avatar"] = (avatar, "image/jpeg") }
        if let header = headerData { files["header"] = (header, "image/jpeg") }

        return try await multipartRequest(
            path: "/api/v1/communities/\(slug)",
            method: "PATCH",
            fields: fields,
            files: files
        )
    }

    /// Permanently deletes a community.  Only admins may call this.
    ///
    /// `DELETE /api/v1/communities/:slug`
    func deleteCommunity(slug: String) async throws {
        try await voidRequest(path: "/api/v1/communities/\(slug)", method: "DELETE")
    }

    /// Joins an open community (or submits a join request for a private one).
    ///
    /// `POST /api/v1/communities/:slug/join`
    func joinCommunity(slug: String) async throws -> RosemountCommunity {
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/join",
            method: "POST",
            body: nil,
            contentType: "application/json"
        )
    }

    /// Removes the authenticated user from a community.
    ///
    /// `POST /api/v1/communities/:slug/leave`
    func leaveCommunity(slug: String) async throws {
        try await voidRequest(path: "/api/v1/communities/\(slug)/leave", method: "POST")
    }

    // MARK: - Feed

    /// Fetches the community post feed with optional pagination.
    ///
    /// `GET /api/v1/communities/:slug/feed`
    func communityFeed(slug: String, maxId: String? = nil, limit: Int = 20) async throws -> [MastodonStatus] {
        var queryItems: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { queryItems.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/feed",
            method: "GET",
            body: nil,
            contentType: "application/json",
            queryItems: queryItems
        )
    }

    /// Returns the list of admin-pinned posts for a community.
    ///
    /// `GET /api/v1/communities/:slug/pinned`
    func pinnedPosts(slug: String) async throws -> [CommunityPinnedPost] {
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/pinned",
            method: "GET",
            body: nil,
            contentType: "application/json"
        )
    }

    /// Pins a post to the top of the community feed.  Requires moderator or admin role.
    ///
    /// `POST /api/v1/communities/:slug/pinned`
    func pinPost(slug: String, statusId: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["status_id": statusId])
        try await voidRequest(path: "/api/v1/communities/\(slug)/pinned", method: "POST", body: body)
    }

    /// Removes a previously pinned post from the community feed.
    ///
    /// `DELETE /api/v1/communities/:slug/pinned/:statusId`
    func unpinPost(slug: String, statusId: String) async throws {
        try await voidRequest(
            path: "/api/v1/communities/\(slug)/pinned/\(statusId)",
            method: "DELETE"
        )
    }

    /// Posts a new status directly into a community's feed.
    ///
    /// `POST /api/v1/communities/:slug/statuses`
    func postToCommunity(
        slug: String,
        content: String,
        mediaIds: [String] = [],
        visibility: String = "public"
    ) async throws -> MastodonStatus {
        var payload: [String: Any] = [
            "status": content,
            "visibility": visibility
        ]
        if !mediaIds.isEmpty {
            payload["media_ids"] = mediaIds
        }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/statuses",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }

    // MARK: - Members

    /// Returns a paginated list of community members.
    ///
    /// `GET /api/v1/communities/:slug/members`
    func members(slug: String, page: Int = 1) async throws -> [CommunityMember] {
        let queryItems = [URLQueryItem(name: "page", value: String(page))]
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/members",
            method: "GET",
            body: nil,
            contentType: "application/json",
            queryItems: queryItems
        )
    }

    /// Promotes or demotes a member to the specified role.  Requires admin role.
    ///
    /// `PATCH /api/v1/communities/:slug/members/:accountId`
    func updateMemberRole(slug: String, accountId: String, role: CommunityRole) async throws -> CommunityMember {
        let body = try JSONSerialization.data(withJSONObject: ["role": role.rawValue])
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/members/\(accountId)",
            method: "PATCH",
            body: body,
            contentType: "application/json"
        )
    }

    /// Removes (kicks) a member from the community.  Requires moderator or admin role.
    ///
    /// `DELETE /api/v1/communities/:slug/members/:accountId`
    func removeMember(slug: String, accountId: String) async throws {
        try await voidRequest(
            path: "/api/v1/communities/\(slug)/members/\(accountId)",
            method: "DELETE"
        )
    }

    // MARK: - Invites

    /// Creates a new invite link, optionally capped by uses or time.
    ///
    /// `POST /api/v1/communities/:slug/invites`
    func createInvite(
        slug: String,
        maxUses: Int? = nil,
        expiresIn: TimeInterval? = nil
    ) async throws -> CommunityInvite {
        var payload: [String: Any] = [:]
        if let maxUses { payload["max_uses"] = maxUses }
        if let expiresIn { payload["expires_in"] = Int(expiresIn) }
        let body = try JSONSerialization.data(withJSONObject: payload)
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/invites",
            method: "POST",
            body: body,
            contentType: "application/json"
        )
    }

    /// Returns all outstanding invites for a community.  Requires moderator or admin role.
    ///
    /// `GET /api/v1/communities/:slug/invites`
    func invites(slug: String) async throws -> [CommunityInvite] {
        return try await apiRequest(
            path: "/api/v1/communities/\(slug)/invites",
            method: "GET",
            body: nil,
            contentType: "application/json"
        )
    }

    /// Revokes an existing invite, preventing further redemptions.
    ///
    /// `DELETE /api/v1/communities/:slug/invites/:inviteId`
    func deleteInvite(slug: String, inviteId: String) async throws {
        try await voidRequest(
            path: "/api/v1/communities/\(slug)/invites/\(inviteId)",
            method: "DELETE"
        )
    }

    /// Redeems an invite code and joins the associated community.
    ///
    /// `POST /api/v1/invites/:code/accept`
    func acceptInvite(code: String) async throws -> RosemountCommunity {
        return try await apiRequest(
            path: "/api/v1/invites/\(code)/accept",
            method: "POST",
            body: nil,
            contentType: "application/json"
        )
    }

    // MARK: - Private helpers

    /// Executes a JSON API request and decodes the response body into `T`.
    private func apiRequest<T: Decodable>(
        path: String,
        method: String,
        body: Data?,
        contentType: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = buildURL(path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
        }

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CommunityAPIError.decodingFailed
        }
    }

    /// Executes a request where the response body is intentionally ignored (e.g. DELETE / leave).
    private func voidRequest(path: String, method: String, body: Data? = nil) async throws {
        let url = buildURL(path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let body {
            request.httpBody = body
        }
        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)
    }

    /// Builds and executes a `multipart/form-data` request, decoding the response into `T`.
    ///
    /// - Parameters:
    ///   - path: API path, e.g. `"/api/v1/communities"`.
    ///   - method: HTTP method string, e.g. `"POST"` or `"PATCH"`.
    ///   - fields: Plain text form fields keyed by their field name.
    ///   - files: Binary file fields; value is `(data, mimeType)` keyed by field name.
    private func multipartRequest<T: Decodable>(
        path: String,
        method: String,
        fields: [String: String],
        files: [String: (Data, String)]
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        let body = buildMultipartBody(fields: fields, files: files, boundary: boundary)

        let url = buildURL(path, queryItems: [])
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        try validateHTTPResponse(response, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CommunityAPIError.decodingFailed
        }
    }

    /// Assembles raw `multipart/form-data` body bytes from field and file dictionaries.
    private func buildMultipartBody(
        fields: [String: String],
        files: [String: (Data, String)],
        boundary: String
    ) -> Data {
        var body = Data()
        let boundaryPrefix = "--\(boundary)\r\n"
        let crlf = "\r\n"

        // Text fields
        for (key, value) in fields {
            body.append(contentsOf: boundaryPrefix.utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)
            body.append(contentsOf: value.utf8)
            body.append(contentsOf: crlf.utf8)
        }

        // File fields
        for (key, (fileData, mimeType)) in files {
            let filename = key  // use the field name as a generic filename
            body.append(contentsOf: boundaryPrefix.utf8)
            body.append(contentsOf: "Content-Disposition: form-data; name=\"\(key)\"; filename=\"\(filename)\"\r\n".utf8)
            body.append(contentsOf: "Content-Type: \(mimeType)\r\n\r\n".utf8)
            body.append(fileData)
            body.append(contentsOf: crlf.utf8)
        }

        body.append(contentsOf: "--\(boundary)--\r\n".utf8)
        return body
    }

    /// Constructs a fully-qualified `URL` from an API path and optional query items.
    private func buildURL(_ path: String, queryItems: [URLQueryItem]) -> URL {
        var components = URLComponents(
            url: instanceURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: true
        ) ?? URLComponents()

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        // Force-unwrap is safe here: instanceURL is validated at init time and the
        // path is always a compile-time constant string within this file.
        return components.url ?? instanceURL.appendingPathComponent(path)
    }

    /// Inspects an `URLResponse` and throws a typed `CommunityAPIError` on failure.
    private func validateHTTPResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299:
            return
        case 401, 403:
            throw CommunityAPIError.forbidden
        case 404:
            throw CommunityAPIError.notFound
        default:
            throw CommunityAPIError.serverError(http.statusCode)
        }
    }
}
