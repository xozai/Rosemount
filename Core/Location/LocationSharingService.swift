// Core/Location/LocationSharingService.swift
// Backend API for location sharing

import CoreLocation
import Foundation

// MARK: - Models

struct LocationShare: Codable, Identifiable {
    let id: String
    let accountId: String
    let handle: String
    let displayName: String
    let avatarURL: String?
    let latitude: Double
    let longitude: Double
    let accuracy: Double
    let sharedAt: String
    let expiresAt: String
    let communityId: String?
    let isLive: Bool

    enum CodingKeys: String, CodingKey {
        case id, handle, accuracy, latitude, longitude
        case accountId = "account_id"
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case sharedAt = "shared_at"
        case expiresAt = "expires_at"
        case communityId = "community_id"
        case isLive = "is_live"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum SharingDuration: Double, CaseIterable, Identifiable {
    case oneHour = 3600
    case fourHours = 14400
    case untilTurnedOff = -1      // sentinel for infinity

    var id: Double { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .fourHours: return "4 Hours"
        case .untilTurnedOff: return "Until I Turn It Off"
        }
    }

    var actualDuration: TimeInterval? {
        rawValue < 0 ? nil : rawValue
    }
}

// MARK: - Coordinate Snapper

struct CoordinateSnapper {
    static func snap(_ coordinate: CLLocationCoordinate2D, gridMeters: Double = 100) -> CLLocationCoordinate2D {
        let degPerMeter = 1.0 / 111_000.0
        let grid = gridMeters * degPerMeter
        let snappedLat = (coordinate.latitude / grid).rounded() * grid
        let snappedLon = (coordinate.longitude / grid).rounded() * grid
        return CLLocationCoordinate2D(latitude: snappedLat, longitude: snappedLon)
    }
}

// MARK: - API Client

actor LocationSharingAPIClient {
    private let instanceURL: URL
    private let accessToken: String
    private let session: URLSession

    init(instanceURL: URL, accessToken: String) {
        self.instanceURL = instanceURL
        self.accessToken = accessToken
        self.session = URLSession.shared
    }

    func startSharing(location: CLLocation, duration: SharingDuration, communityId: String?) async throws -> LocationShare {
        let snapped = CoordinateSnapper.snap(location.coordinate)
        var body: [String: Any] = [
            "latitude": snapped.latitude,
            "longitude": snapped.longitude,
            "accuracy": location.horizontalAccuracy,
            "is_live": true
        ]
        if let dur = duration.actualDuration { body["duration"] = dur }
        if let cid = communityId { body["community_id"] = cid }
        return try await post(path: "api/v1/location/share", body: body)
    }

    func updateLocation(_ location: CLLocation) async throws {
        let snapped = CoordinateSnapper.snap(location.coordinate)
        let body: [String: Any] = [
            "latitude": snapped.latitude,
            "longitude": snapped.longitude,
            "accuracy": location.horizontalAccuracy
        ]
        var req = request(method: "PUT", path: "api/v1/location/share/current")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        _ = try await session.data(for: req)
    }

    func stopSharing() async throws {
        var req = request(method: "DELETE", path: "api/v1/location/share/current")
        _ = try await session.data(for: req)
    }

    func communityLocations(communityId: String) async throws -> [LocationShare] {
        try await get(path: "api/v1/communities/\(communityId)/locations")
    }

    func followedLocations() async throws -> [LocationShare] {
        try await get(path: "api/v1/location/following")
    }

    // MARK: Helpers

    private func get<T: Decodable>(path: String) async throws -> T {
        let req = request(method: "GET", path: path)
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func post<T: Decodable>(path: String, body: [String: Any]) async throws -> T {
        var req = request(method: "POST", path: path)
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: req)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(method: String, path: String) -> URLRequest {
        var req = URLRequest(url: instanceURL.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }
}
