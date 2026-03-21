// Core/Events/EventAPIClient.swift
// REST API client for events and RSVPs

import Foundation

enum EventAPIError: Error, LocalizedError {
    case notFound
    case forbidden
    case serverError(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .notFound: return "Event not found"
        case .forbidden: return "You don't have permission to do that"
        case .serverError(let code): return "Server error (\(code))"
        case .decodingFailed: return "Could not read server response"
        }
    }
}

actor EventAPIClient {
    private let instanceURL: URL
    private let accessToken: String
    private let session = URLSession.shared
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return d
    }()

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
    }

    func communityEvents(slug: String, upcoming: Bool = true, page: Int = 1) async throws -> [RosemountEvent] {
        try await get(path: "api/v1/communities/\(slug)/events", query: ["upcoming": upcoming ? "true" : "false", "page": "\(page)"])
    }

    func event(id: String) async throws -> RosemountEvent {
        try await get(path: "api/v1/events/\(id)")
    }

    func createEvent(
        communitySlug: String,
        title: String,
        description: String,
        startDate: Date,
        endDate: Date?,
        timezone: String,
        location: EventLocation?,
        isOnline: Bool,
        onlineURL: String?,
        bannerData: Data?
    ) async throws -> RosemountEvent {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        var body: [String: Any] = [
            "title": title,
            "description": description,
            "start_date": iso.string(from: startDate),
            "timezone": timezone,
            "is_online": isOnline
        ]
        if let end = endDate { body["end_date"] = iso.string(from: end) }
        if let url = onlineURL { body["online_url"] = url }
        if let loc = location {
            body["location_name"] = loc.name
            if let addr = loc.address { body["location_address"] = addr }
            if let lat = loc.latitude, let lon = loc.longitude {
                body["latitude"] = lat
                body["longitude"] = lon
            }
        }
        return try await post(path: "api/v1/communities/\(communitySlug)/events", body: body)
    }

    func rsvp(eventId: String, status: RSVPStatus) async throws -> RosemountEvent {
        try await post(path: "api/v1/events/\(eventId)/rsvp", body: ["status": status.rawValue])
    }

    func attendees(eventId: String, status: RSVPStatus? = nil, page: Int = 1) async throws -> [MastodonAccount] {
        var query = ["page": "\(page)"]
        if let s = status { query["status"] = s.rawValue }
        return try await get(path: "api/v1/events/\(eventId)/attendees", query: query)
    }

    func deleteEvent(id: String) async throws {
        var req = makeRequest(method: "DELETE", path: "api/v1/events/\(id)")
        let (_, resp) = try await session.data(for: req)
        try checkStatus(resp)
    }

    // MARK: Helpers

    private func get<T: Decodable>(path: String, query: [String: String] = [:]) async throws -> T {
        var comps = URLComponents(url: instanceURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await session.data(for: req)
        try checkStatus(resp)
        do { return try decoder.decode(T.self, from: data) } catch { throw EventAPIError.decodingFailed }
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var req = makeRequest(method: "POST", path: path)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        try checkStatus(resp)
        do { return try decoder.decode(T.self, from: data) } catch { throw EventAPIError.decodingFailed }
    }

    private func makeRequest(method: String, path: String) -> URLRequest {
        var req = URLRequest(url: instanceURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        switch http.statusCode {
        case 200...299: break
        case 404: throw EventAPIError.notFound
        case 403: throw EventAPIError.forbidden
        default: throw EventAPIError.serverError(http.statusCode)
        }
    }
}
