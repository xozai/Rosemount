// Core/Stories/StoriesAPIClient.swift
// Rosemount
//
// Async/await actor client for the Rosemount Stories REST API.
// Endpoints: feed, my stories, create, delete, view, react, viewers.
//
// Swift 5.10 | iOS 17.0+

import Foundation

// RosemountStory  — defined in Core/Stories/Models/RosemountStory.swift
// MastodonAccount — defined in Core/Mastodon/Models/MastodonAccount.swift

// MARK: - StoriesAPIClient

actor StoriesAPIClient {

    // MARK: - Dependencies

    private let instanceURL: URL
    private let accessToken: String
    private let session: URLSession

    // MARK: - Init

    init(instanceURL: URL, accessToken: String, session: URLSession = .shared) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
        self.session = session
    }

    // MARK: - Feed

    /// Returns the authenticated user's story feed, grouped by account.
    /// GET /api/v1/stories/feed
    func feedStories() async throws -> [StoryGroup] {
        try await get("api/v1/stories/feed")
    }

    /// Returns only the authenticated user's own stories.
    /// GET /api/v1/stories/me
    func myStories() async throws -> [RosemountStory] {
        try await get("api/v1/stories/me")
    }

    // MARK: - Create

    /// Uploads a new story with optional caption and background colour.
    /// POST /api/v1/stories  (multipart/form-data)
    func createStory(
        mediaData: Data,
        mediaType: StoryMediaType,
        caption: String?,
        backgroundColor: String?
    ) async throws -> RosemountStory {
        let boundary = UUID().uuidString
        let url = instanceURL.appendingPathComponent("api/v1/stories")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let mime = mediaType == .image ? "image/jpeg" : "video/mp4"
        let ext  = mediaType == .image ? "jpg" : "mp4"

        var body = Data()
        body.appendFormField(name: "media", filename: "story.\(ext)", mime: mime, data: mediaData, boundary: boundary)
        if let caption         { body.appendTextField(name: "caption",          value: caption,          boundary: boundary) }
        if let backgroundColor { body.appendTextField(name: "background_color", value: backgroundColor, boundary: boundary) }
        body.append("--\(boundary)--\r\n".utf8Data)

        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        return try JSONDecoder.mastodon.decode(RosemountStory.self, from: data)
    }

    // MARK: - Mutate

    /// Marks a story as viewed by the authenticated user.
    /// POST /api/v1/stories/:id/view
    func viewStory(id: String) async throws {
        let req = try authorisedRequest("api/v1/stories/\(id)/view", method: "POST")
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    /// Sends an emoji reaction to a story.
    /// POST /api/v1/stories/:id/react
    func reactToStory(id: String, emoji: String) async throws {
        var req = try authorisedRequest("api/v1/stories/\(id)/react", method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["emoji": emoji])
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    /// Deletes one of the authenticated user's own stories.
    /// DELETE /api/v1/stories/:id
    func deleteStory(id: String) async throws {
        let req = try authorisedRequest("api/v1/stories/\(id)", method: "DELETE")
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
    }

    // MARK: - Viewers

    /// Returns accounts that have viewed the given story.
    /// GET /api/v1/stories/:id/viewers
    func viewers(storyId: String) async throws -> [MastodonAccount] {
        try await get("api/v1/stories/\(storyId)/viewers")
    }

    // MARK: - Private Helpers

    private func get<T: Decodable>(_ path: String) async throws -> T {
        let req = try authorisedRequest(path, method: "GET")
        let (data, response) = try await session.data(for: req)
        try validateResponse(response, data: data)
        do {
            return try JSONDecoder.mastodon.decode(T.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }

    private func authorisedRequest(_ path: String, method: String) throws -> URLRequest {
        let url = instanceURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }
    }
}

// MARK: - Multipart helpers

private extension Data {
    mutating func appendFormField(name: String, filename: String, mime: String, data: Data, boundary: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8Data)
        append("Content-Type: \(mime)\r\n\r\n".utf8Data)
        append(data)
        append("\r\n".utf8Data)
    }

    mutating func appendTextField(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".utf8Data)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8Data)
        append("\(value)\r\n".utf8Data)
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
