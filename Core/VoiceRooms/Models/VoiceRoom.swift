// Core/VoiceRooms/Models/VoiceRoom.swift
// Voice room model

import Foundation

enum VoiceRoomStatus: String, Codable {
    case live, scheduled, ended
}

struct VoiceRoomSpeaker: Codable, Identifiable, Hashable {
    let id: String
    let account: MastodonAccount
    var isMuted: Bool
    var isSpeaking: Bool
    var isModerator: Bool
    var handRaised: Bool

    enum CodingKeys: String, CodingKey {
        case id, account
        case isMuted = "is_muted"
        case isSpeaking = "is_speaking"
        case isModerator = "is_moderator"
        case handRaised = "hand_raised"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: VoiceRoomSpeaker, rhs: VoiceRoomSpeaker) -> Bool { lhs.id == rhs.id }
}

struct VoiceRoom: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let communityId: String?
    let communitySlug: String?
    let hostId: String
    let status: VoiceRoomStatus
    let speakers: [VoiceRoomSpeaker]
    let listenerCount: Int
    let maxSpeakers: Int
    let createdAt: String
    let scheduledFor: String?
    let topicTags: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, status, speakers
        case communityId = "community_id"
        case communitySlug = "community_slug"
        case hostId = "host_id"
        case listenerCount = "listener_count"
        case maxSpeakers = "max_speakers"
        case createdAt = "created_at"
        case scheduledFor = "scheduled_for"
        case topicTags = "topic_tags"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: VoiceRoom, rhs: VoiceRoom) -> Bool { lhs.id == rhs.id }

    var isLive: Bool { status == .live }
    var speakerCount: Int { speakers.count }
}

// WebRTC Signaling message types
enum SignalingMessageType: String, Codable {
    case offer, answer, candidate, join, leave, mute, unmute, raiseHand, lowerHand, kick, promote
}

struct SignalingMessage: Codable {
    let type: SignalingMessageType
    let roomId: String
    let senderId: String
    let targetId: String?
    let payload: String?   // JSON string for SDP offer/answer or ICE candidate

    enum CodingKeys: String, CodingKey {
        case type, payload
        case roomId = "room_id"
        case senderId = "sender_id"
        case targetId = "target_id"
    }
}

// MARK: - Voice Room API Client

actor VoiceRoomAPIClient {
    private let instanceURL: URL
    private let accessToken: String
    private let session = URLSession.shared

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
    }

    func liveRooms(communitySlug: String? = nil) async throws -> [VoiceRoom] {
        var path = "api/v1/voice/rooms?status=live"
        if let slug = communitySlug { path += "&community=\(slug)" }
        return try await get(path: path)
    }

    func room(id: String) async throws -> VoiceRoom {
        try await get(path: "api/v1/voice/rooms/\(id)")
    }

    func createRoom(title: String, communitySlug: String?, topicTags: [String]) async throws -> VoiceRoom {
        var body: [String: Any] = ["title": title, "topic_tags": topicTags]
        if let slug = communitySlug { body["community_slug"] = slug }
        return try await post(path: "api/v1/voice/rooms", body: body)
    }

    func joinRoom(id: String) async throws -> VoiceRoom {
        try await post(path: "api/v1/voice/rooms/\(id)/join", body: [:])
    }

    func leaveRoom(id: String) async throws {
        var req = makeRequest(method: "POST", path: "api/v1/voice/rooms/\(id)/leave")
        _ = try await session.data(for: req)
    }

    func endRoom(id: String) async throws {
        var req = makeRequest(method: "DELETE", path: "api/v1/voice/rooms/\(id)")
        _ = try await session.data(for: req)
    }

    func signalingURL(roomId: String) -> URL {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.scheme = instanceURL.scheme == "https" ? "wss" : "ws"
        components.path = "/api/v1/voice/rooms/\(roomId)/signal"
        components.queryItems = [URLQueryItem(name: "token", value: accessToken)]
        return components.url!
    }

    private func get<T: Decodable>(path: String) async throws -> T {
        var req = URLRequest(url: instanceURL.appendingPathComponent(path))
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await session.data(for: req)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var req = makeRequest(method: "POST", path: path)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        let dec = JSONDecoder(); dec.keyDecodingStrategy = .convertFromSnakeCase
        return try dec.decode(T.self, from: data)
    }

    private func makeRequest(method: String, path: String) -> URLRequest {
        var req = URLRequest(url: instanceURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }
}
