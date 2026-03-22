// RosemountAPIClient.swift
// Rosemount
//
// Lightweight API client for the native Rosemount back-end.
// Handles account registration and returns credentials compatible
// with the rest of the app (Mastodon-compatible API).
//
// Swift 5.10 | iOS 17.0+

import Foundation

// MARK: - RosemountAPIError

enum RosemountAPIError: Error, LocalizedError {
    case invalidResponse
    case httpError(statusCode: Int, message: String)
    case decodingError(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .httpError(let code, let message):
            return "Server error \(code): \(message)"
        case .decodingError(let err):
            return "Could not read the server response: \(err.localizedDescription)"
        }
    }
}

// MARK: - Registration Types

struct RosemountRegistrationRequest: Encodable {
    let username: String
    let email: String
    let password: String
    let agreement: Bool = true
    let locale: String = Locale.current.identifier
}

struct RosemountRegistrationResponse: Decodable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let instanceURL: String
    let handle: String
    let displayName: String?
    let avatarURL: String?
    let actorURL: String?

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case scope
        case instanceURL  = "instance_url"
        case handle
        case displayName  = "display_name"
        case avatarURL    = "avatar_url"
        case actorURL     = "actor_url"
    }
}

// MARK: - RosemountAPIClient

actor RosemountAPIClient {

    static let baseURL = URL(string: "https://api.rosemount.social")!

    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        let d = JSONDecoder()
        self.decoder = d
    }

    // MARK: - Registration

    /// Registers a new native Rosemount account.
    ///
    /// On success, returns a `RosemountRegistrationResponse` whose `accessToken`
    /// can be used immediately to call Mastodon-compatible endpoints on
    /// `https://api.rosemount.social`.
    func register(
        username: String,
        email: String,
        password: String
    ) async throws -> RosemountRegistrationResponse {
        let url = Self.baseURL.appendingPathComponent("/api/v1/accounts")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body = RosemountRegistrationRequest(
            username: username,
            email: email,
            password: password
        )
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw RosemountAPIError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            // Try to extract a message from the error body.
            let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"]
                ?? String(data: data, encoding: .utf8)
                ?? "Unknown error"
            throw RosemountAPIError.httpError(statusCode: http.statusCode, message: message)
        }

        do {
            return try decoder.decode(RosemountRegistrationResponse.self, from: data)
        } catch {
            throw RosemountAPIError.decodingError(underlying: error)
        }
    }

    // MARK: - Username Availability

    /// Returns `true` when the username is available on rosemount.social.
    func isUsernameAvailable(_ username: String) async throws -> Bool {
        guard var components = URLComponents(
            url: Self.baseURL.appendingPathComponent("/api/v1/accounts/check_username"),
            resolvingAgainstBaseURL: false
        ) else { return false }
        components.queryItems = [URLQueryItem(name: "username", value: username)]

        guard let url = components.url else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            return false
        }
        struct AvailabilityResponse: Decodable { let available: Bool }
        return (try? decoder.decode(AvailabilityResponse.self, from: data))?.available ?? false
    }
}
