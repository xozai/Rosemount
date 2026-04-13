// MastodonAPIClient+Phase2.swift
// Rosemount
//
// Phase 2 extension on MastodonAPIClient.
//
// Adds the following endpoints not covered by the base client or other
// in-file extensions:
//
//   Accounts:
//     accountStatuses(id:maxId:limit:excludeReplies:)  — with excludeReplies param
//     updateCredentials(displayName:note:avatarData:headerData:)
//
//   Conversations (DMs):
//     conversations(maxId:limit:)
//     markConversationRead(id:)
//     deleteConversation(id:)
//
// Note on existing method coverage:
//   followers(id:maxId:limit:)    — defined in Features/Profile/FollowersView.swift
//   following(id:maxId:limit:)    — defined in Features/Profile/FollowersView.swift
//   accountStatuses(id:maxId:limit:) — defined in Features/Profile/ProfileViewModel.swift
//   statusContext(id:)            — defined in Features/Messaging/MessageThreadView.swift
//                                   (returns MastodonStatusContext)
//
// Types referenced from other files:
//   MastodonAPIClient    — Core/Mastodon/MastodonAPIClient.swift
//   MastodonStatus       — Core/Mastodon/Models/MastodonStatus.swift
//   MastodonAccount      — Core/Mastodon/Models/MastodonAccount.swift
//   MastodonConversation — Core/Mastodon/Models/MastodonConversation.swift
//   MastodonClientError  — Core/Mastodon/MastodonAPIClient.swift
//
// Swift 5.10 | iOS 17.0+

import Foundation

// MARK: - MastodonAPIClient Phase 2 Extension

extension MastodonAPIClient {

    // MARK: - File-private Helpers

    /// Returns a correctly configured JSON decoder matching the one used inside MastodonAPIClient.
    fileprivate var p2Decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Builds a complete URL by appending `path` to `instanceURL` with optional query items.
    fileprivate func p2BuildURL(_ path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        let base = instanceURL.appendingPathComponent(
            path.hasPrefix("/") ? String(path.dropFirst()) : path
        )
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MastodonClientError.invalidURL
        }
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw MastodonClientError.invalidURL
        }
        return url
    }

    /// Throws `MastodonClientError.httpError` when the response is non-2xx.
    fileprivate func p2Validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }

    /// Executes a GET request and decodes the response body into `T`.
    fileprivate func p2Get<T: Decodable>(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        let url = try p2BuildURL(path, queryItems: queryItems)
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",      forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try p2Decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Executes a POST request with an optional JSON body and decodes the response.
    fileprivate func p2Post<T: Decodable>(
        _ path: String,
        body: [String: Any]? = nil
    ) async throws -> T {
        let url = try p2BuildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",      forHTTPHeaderField: "Accept")

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try p2Decoder.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    /// Executes a DELETE request and discards the response body.
    fileprivate func p2DeleteVoid(_ path: String) async throws {
        let url = try p2BuildURL(path)
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",      forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)
    }

    // MARK: - Accounts

    /// Returns the list of statuses posted by the account with `id`, with an
    /// optional `excludeReplies` flag.
    ///
    /// This is the Phase 2 variant of `accountStatuses(id:maxId:limit:)` defined
    /// in `Features/Profile/ProfileViewModel.swift`.  It adds the `excludeReplies`
    /// parameter which is absent from the base version.
    ///
    /// - Parameters:
    ///   - id: The account's numeric string ID.
    ///   - maxId: Return results older than this status ID (pagination cursor).
    ///   - limit: Maximum number of statuses to return. Default `20`.
    ///   - excludeReplies: When `true`, reply statuses are omitted. Default `true`.
    func accountStatuses(
        id: String,
        maxId: String? = nil,
        limit: Int = 20,
        excludeReplies: Bool = true
    ) async throws -> [MastodonStatus] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit",           value: String(limit)),
            URLQueryItem(name: "exclude_replies", value: excludeReplies ? "true" : "false"),
        ]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/accounts/\(id)/statuses", queryItems: items)
    }

    /// Updates the authenticated user's own profile via
    /// PATCH `/api/v1/accounts/update_credentials`.
    ///
    /// All parameters are optional; only non-`nil` values are sent in the
    /// multipart body.
    ///
    /// - Parameters:
    ///   - displayName: New display name string.
    ///   - note: New bio / note (plain text; the server converts it to HTML).
    ///   - avatarData: JPEG or PNG image data for the avatar.
    ///   - headerData: JPEG or PNG image data for the header banner.
    ///   - fields: Up to 4 profile metadata fields as (name, value) pairs.
    ///     Sent as `fields_attributes[i][name]` / `fields_attributes[i][value]`.
    /// - Returns: The updated `MastodonAccount` entity.
    func updateCredentials(
        displayName: String?,
        note: String?,
        avatarData: Data?,
        headerData: Data?,
        fields: [(name: String, value: String)]? = nil
    ) async throws -> MastodonAccount {
        let boundary = "RosemountP2Boundary-\(UUID().uuidString)"
        let url = try p2BuildURL("/api/v1/accounts/update_credentials")

        var req = URLRequest(url: url)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",      forHTTPHeaderField: "Accept")
        req.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )

        var body = Data()

        func appendText(name: String, value: String) {
            body.append("--\(boundary)\r\n".p2UTF8)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".p2UTF8)
            body.append(value.p2UTF8)
            body.append("\r\n".p2UTF8)
        }

        func appendFile(name: String, filename: String, mimeType: String, fileData: Data) {
            body.append("--\(boundary)\r\n".p2UTF8)
            body.append(
                "Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n"
                    .p2UTF8
            )
            body.append("Content-Type: \(mimeType)\r\n\r\n".p2UTF8)
            body.append(fileData)
            body.append("\r\n".p2UTF8)
        }

        if let displayName { appendText(name: "display_name", value: displayName) }
        if let note        { appendText(name: "note",         value: note) }
        if let avatarData  { appendFile(name: "avatar",  filename: "avatar.jpg",  mimeType: "image/jpeg", fileData: avatarData) }
        if let headerData  { appendFile(name: "header",  filename: "header.jpg",  mimeType: "image/jpeg", fileData: headerData) }
        // Profile metadata fields — Mastodon accepts up to 4.
        if let fields {
            for (i, field) in fields.prefix(4).enumerated() {
                appendText(name: "fields_attributes[\(i)][name]",  value: field.name)
                appendText(name: "fields_attributes[\(i)][value]", value: field.value)
            }
        }

        body.append("--\(boundary)--\r\n".p2UTF8)
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        try p2Validate(response, data: data)

        do {
            return try p2Decoder.decode(MastodonAccount.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    // MARK: - Conversations (Direct Messages)

    /// Returns the direct-message conversations for the authenticated user.
    ///
    /// Corresponds to GET `/api/v1/conversations`.
    ///
    /// - Parameters:
    ///   - maxId: Return results older than this conversation ID (pagination cursor).
    ///   - limit: Maximum number of conversations to return. Default `20`.
    func conversations(
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonConversation] {
        var items: [URLQueryItem] = [URLQueryItem(name: "limit", value: String(limit))]
        if let maxId { items.append(URLQueryItem(name: "max_id", value: maxId)) }
        return try await p2Get("/api/v1/conversations", queryItems: items)
    }

    /// Marks the conversation with the given `id` as read and returns the
    /// updated conversation entity.
    ///
    /// Corresponds to POST `/api/v1/conversations/:id/read`.
    func markConversationRead(id: String) async throws -> MastodonConversation {
        try await p2Post("/api/v1/conversations/\(id)/read")
    }

    /// Removes a conversation from the authenticated user's inbox.
    ///
    /// Corresponds to DELETE `/api/v1/conversations/:id`.
    func deleteConversation(id: String) async throws {
        try await p2DeleteVoid("/api/v1/conversations/\(id)")
    }
}

// MARK: - UTF-8 Data Helper (file-private)

private extension String {
    /// Encodes the string as UTF-8 `Data`. Used in multipart body construction.
    var p2UTF8: Data { Data(utf8) }
}

// MARK: - Convenience init from AccountCredential

extension MastodonAPIClient {
    /// Convenience initialiser that builds a client directly from an `AccountCredential`.
    init(credential: AccountCredential) {
        self.init(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }
}

// MARK: - Moderation

extension MastodonAPIClient {

    /// Reports a status to the instance moderators.
    ///
    /// Corresponds to POST `/api/v1/reports`.
    func reportStatus(
        accountId: String,
        statusIds: [String],
        comment: String? = nil
    ) async throws {
        var body: [String: Any] = [
            "account_id": accountId,
            "status_ids": statusIds,
        ]
        if let comment { body["comment"] = comment }

        struct ReportResponse: Decodable { let id: String }
        let _: ReportResponse = try await p2Post("/api/v1/reports", body: body)
    }
}
