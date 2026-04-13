// MastodonAPIClientTests.swift
// Rosemount
//
// Unit tests for MastodonAPIClient URL construction and error mapping.
//
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

final class MastodonAPIClientTests: XCTestCase {

    // MARK: - buildURL via URLComponents (mirrors internal logic)

    /// Replicates the internal buildURL logic so we can test URL construction
    /// without touching private actor internals.
    private func buildURL(
        base: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        let pathSuffix = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let appended = base.appendingPathComponent(pathSuffix)
        guard var components = URLComponents(url: appended, resolvingAgainstBaseURL: false) else {
            throw MastodonClientError.invalidURL
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw MastodonClientError.invalidURL }
        return url
    }

    // MARK: - Valid URL construction

    func testBuildURLWithLeadingSlash() throws {
        let base = URL(string: "https://mastodon.social")!
        let url = try buildURL(base: base, path: "/api/v1/timelines/home")
        XCTAssertEqual(url.host, "mastodon.social")
        XCTAssertEqual(url.path, "/api/v1/timelines/home")
    }

    func testBuildURLWithoutLeadingSlash() throws {
        let base = URL(string: "https://mastodon.social")!
        let url = try buildURL(base: base, path: "api/v1/timelines/home")
        XCTAssertEqual(url.path, "/api/v1/timelines/home")
    }

    func testBuildURLWithQueryItems() throws {
        let base = URL(string: "https://mastodon.social")!
        let url = try buildURL(
            base: base,
            path: "/api/v1/timelines/home",
            queryItems: [
                URLQueryItem(name: "limit", value: "20"),
                URLQueryItem(name: "max_id", value: "109876543210")
            ]
        )
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let items = components?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "limit", value: "20")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "max_id", value: "109876543210")))
    }

    func testBuildURLSchemePreserved() throws {
        let base = URL(string: "https://mastodon.social")!
        let url = try buildURL(base: base, path: "/api/v1/accounts/verify_credentials")
        XCTAssertEqual(url.scheme, "https")
    }

    func testBuildURLNoQueryItems() throws {
        let base = URL(string: "https://fosstodon.org")!
        let url = try buildURL(base: base, path: "/api/v1/instance")
        // Should have no query string when no items supplied
        XCTAssertNil(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
    }

    // MARK: - MastodonClientError cases

    func testInvalidURLErrorDescription() {
        let error = MastodonClientError.invalidURL
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testUnauthorizedErrorDescription() {
        let error = MastodonClientError.unauthorized
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.lowercased().contains("sign in"))
    }

    func testRateLimitedWithRetryAfter() {
        let error = MastodonClientError.rateLimited(retryAfter: 30)
        XCTAssertTrue(error.errorDescription?.contains("30") ?? false)
    }

    func testRateLimitedWithoutRetryAfter() {
        let error = MastodonClientError.rateLimited(retryAfter: nil)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertFalse(error.errorDescription!.isEmpty)
    }

    func testServerErrorDescription() {
        let error = MastodonClientError.serverError(code: 503)
        XCTAssertTrue(error.errorDescription?.contains("503") ?? false)
    }

    func testHttpErrorDescription() {
        let error = MastodonClientError.httpError(statusCode: 422, body: "Validation failed")
        XCTAssertTrue(error.errorDescription?.contains("422") ?? false)
        XCTAssertTrue(error.errorDescription?.contains("Validation failed") ?? false)
    }

    // MARK: - MastodonAPIClient initialization

    func testAPIClientInit() async throws {
        let base = URL(string: "https://mastodon.social")!
        let client = MastodonAPIClient(instanceURL: base, accessToken: "test-token")
        // Actor is created without throwing — just verify construction succeeds.
        _ = client
    }

    func testAPIClientAcceptsCustomSession() async throws {
        let base = URL(string: "https://mastodon.social")!
        let config = URLSessionConfiguration.ephemeral
        let session = URLSession(configuration: config)
        let client = MastodonAPIClient(instanceURL: base, accessToken: "tok", session: session)
        _ = client
    }

    // MARK: - MastodonNotificationType decoding

    func testNotificationTypeDecoding() throws {
        let types: [String: MastodonNotificationType] = [
            "mention": .mention,
            "status": .status,
            "reblog": .reblog,
            "follow": .follow,
            "follow_request": .followRequest,
            "favourite": .favourite,
            "poll": .poll,
            "update": .update
        ]
        for (raw, expected) in types {
            let data = "\"\(raw)\"".data(using: .utf8)!
            let decoded = try JSONDecoder().decode(MastodonNotificationType.self, from: data)
            XCTAssertEqual(decoded, expected, "Failed for raw value '\(raw)'")
        }
    }

    // MARK: - MastodonSearchResults decoding

    func testSearchResultsDecoding() throws {
        let json = """
        {
          "accounts": [],
          "statuses": [],
          "hashtags": []
        }
        """.data(using: .utf8)!
        let results = try JSONDecoder().decode(MastodonSearchResults.self, from: json)
        XCTAssertTrue(results.accounts.isEmpty)
        XCTAssertTrue(results.statuses.isEmpty)
        XCTAssertTrue(results.hashtags.isEmpty)
    }
}
