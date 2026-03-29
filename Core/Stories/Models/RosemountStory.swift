// Core/Stories/Models/RosemountStory.swift
// 24-hour ephemeral story model

import Foundation

enum StoryMediaType: String, Codable {
    case image, video
}

struct StoryReaction: Codable {
    let emoji: String
    let count: Int
    let hasReacted: Bool

    enum CodingKeys: String, CodingKey {
        case emoji, count
        case hasReacted = "has_reacted"
    }
}

struct RosemountStory: Codable, Identifiable, Hashable {
    let id: String
    let account: MastodonAccount
    let mediaURL: String
    let mediaType: StoryMediaType
    let duration: Double
    let caption: String?
    let backgroundColor: String?
    let createdAt: String
    let expiresAt: String
    let viewCount: Int
    let hasViewed: Bool
    let reactions: [StoryReaction]

    enum CodingKeys: String, CodingKey {
        case id, account, duration, caption, reactions
        case mediaURL = "media_url"
        case mediaType = "media_type"
        case backgroundColor = "background_color"
        case createdAt = "created_at"
        case expiresAt = "expires_at"
        case viewCount = "view_count"
        case hasViewed = "has_viewed"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: RosemountStory, rhs: RosemountStory) -> Bool { lhs.id == rhs.id }
}

extension RosemountStory {
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    var createdDate: Date? {
        Self.iso8601.date(from: createdAt) ?? Self.iso8601Plain.date(from: createdAt)
    }

    var expiresDate: Date? {
        Self.iso8601.date(from: expiresAt) ?? Self.iso8601Plain.date(from: expiresAt)
    }

    var isExpired: Bool { (expiresDate ?? Date()) < Date() }

    var timeRemaining: String {
        guard let expires = expiresDate else { return "" }
        let remaining = expires.timeIntervalSinceNow
        if remaining <= 0 { return "Expired" }
        let hours = Int(remaining / 3600)
        if hours > 0 { return "\(hours)h remaining" }
        let minutes = Int(remaining / 60)
        return "\(minutes)m remaining"
    }

    var mediaImageURL: URL? { URL(string: mediaURL) }
}

struct StoryGroup: Identifiable, Equatable {
    var id: String { account.id }
    let account: MastodonAccount
    var stories: [RosemountStory]

    var hasUnviewed: Bool { stories.contains { !$0.hasViewed } }
    var latestStory: RosemountStory? { stories.max { $0.createdAt < $1.createdAt } }
}

// MARK: - Stories API Client

actor StoriesAPIClient {
    private let instanceURL: URL
    private let accessToken: String
    private let session = URLSession.shared

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
    }

    func feedStories() async throws -> [StoryGroup] {
        try await get(path: "api/v1/stories/feed")
    }

    func myStories() async throws -> [RosemountStory] {
        try await get(path: "api/v1/stories/me")
    }

    func createStory(mediaData: Data, mediaType: StoryMediaType, caption: String?, backgroundColor: String?) async throws -> RosemountStory {
        var req = URLRequest(url: instanceURL.appendingPathComponent("api/v1/stories"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let boundary = UUID().uuidString
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        let mime = mediaType == .image ? "image/jpeg" : "video/mp4"
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"media\"; filename=\"story.\(mediaType == .image ? "jpg" : "mp4")\"\r\nContent-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(mediaData)
        body.append("\r\n".data(using: .utf8)!)
        if let cap = caption {
            body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n\(cap)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(RosemountStory.self, from: data)
    }

    func deleteStory(id: String) async throws {
        var req = URLRequest(url: instanceURL.appendingPathComponent("api/v1/stories/\(id)"))
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    func viewStory(id: String) async throws {
        var req = URLRequest(url: instanceURL.appendingPathComponent("api/v1/stories/\(id)/view"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await session.data(for: req)
    }

    func reactToStory(id: String, emoji: String) async throws {
        var req = URLRequest(url: instanceURL.appendingPathComponent("api/v1/stories/\(id)/react"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["emoji": emoji])
        _ = try await session.data(for: req)
    }

    func viewers(storyId: String) async throws -> [MastodonAccount] {
        try await get(path: "api/v1/stories/\(storyId)/viewers")
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        var req = URLRequest(url: instanceURL.appendingPathComponent(path))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
