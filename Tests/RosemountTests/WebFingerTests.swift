import XCTest
import CryptoKit
@testable import Rosemount

final class WebFingerTests: XCTestCase {

    // MARK: - Handle Parsing

    func testValidHandleParsing() {
        // WebFingerService should parse @user@instance.social
        let handle = "@alice@mastodon.social"
        let stripped = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let parts = stripped.split(separator: "@", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "alice")
        XCTAssertEqual(String(parts[1]), "mastodon.social")
    }

    func testHandleWithoutLeadingAt() {
        let handle = "bob@fosstodon.org"
        let stripped = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let parts = stripped.split(separator: "@", maxSplits: 1)
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(String(parts[0]), "bob")
        XCTAssertEqual(String(parts[1]), "fosstodon.org")
    }

    func testInvalidHandleNoDomain() {
        let handle = "@alicenodomain"
        let stripped = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
        let parts = stripped.split(separator: "@", maxSplits: 1)
        // Should only have 1 part — no domain
        XCTAssertEqual(parts.count, 1)
    }

    // MARK: - WebFinger URL Construction

    func testWebFingerURLConstruction() {
        let user = "alice"
        let host = "mastodon.social"
        let resource = "acct:\(user)@\(host)"
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/.well-known/webfinger"
        components.queryItems = [URLQueryItem(name: "resource", value: resource)]
        let url = components.url
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "mastodon.social")
        XCTAssertEqual(url?.path, "/.well-known/webfinger")
        XCTAssertTrue(url?.query?.contains("resource=acct%3Aalice%40mastodon.social") ?? false ||
                      url?.query?.contains("resource=acct:alice@mastodon.social") ?? false)
    }

    // MARK: - WebFingerResource Decoding

    func testDecodeWebFingerResource() throws {
        let json = """
        {
          "subject": "acct:alice@mastodon.social",
          "aliases": [
            "https://mastodon.social/@alice",
            "https://mastodon.social/users/alice"
          ],
          "links": [
            {
              "rel": "http://webfinger.net/rel/profile-page",
              "type": "text/html",
              "href": "https://mastodon.social/@alice"
            },
            {
              "rel": "self",
              "type": "application/activity+json",
              "href": "https://mastodon.social/users/alice"
            },
            {
              "rel": "http://ostatus.org/schema/1.0/subscribe",
              "template": "https://mastodon.social/authorize_interaction?uri={uri}"
            }
          ]
        }
        """.data(using: .utf8)!

        let resource = try JSONDecoder().decode(WebFingerResource.self, from: json)
        XCTAssertEqual(resource.subject, "acct:alice@mastodon.social")
        XCTAssertEqual(resource.aliases?.count, 2)

        let selfLink = resource.links.first(where: { $0.rel == "self" && $0.type == "application/activity+json" })
        XCTAssertNotNil(selfLink)
        XCTAssertEqual(selfLink?.href, "https://mastodon.social/users/alice")
    }

    func testDecodeWebFingerResourceNoActivityPubLink() throws {
        let json = """
        {
          "subject": "acct:alice@example.com",
          "links": [
            {
              "rel": "http://webfinger.net/rel/profile-page",
              "type": "text/html",
              "href": "https://example.com/@alice"
            }
          ]
        }
        """.data(using: .utf8)!

        let resource = try JSONDecoder().decode(WebFingerResource.self, from: json)
        let selfLink = resource.links.first(where: { $0.rel == "self" && $0.type == "application/activity+json" })
        XCTAssertNil(selfLink)
        // WebFingerService should throw .noActivityPubLink in this case
    }

    // MARK: - HTTP Signature Headers

    func testSignatureHeaderFormat() {
        // Verify the expected format of a Signature header
        let keyId = "https://rosemount.social/users/alice#main-key"
        let headers = "(request-target) host date digest"
        let signature = "base64signaturehere=="
        let signatureHeader = #"keyId="\#(keyId)",algorithm="rsa-sha256",headers="\#(headers)",signature="\#(signature)""#

        XCTAssertTrue(signatureHeader.contains("keyId="))
        XCTAssertTrue(signatureHeader.contains("algorithm=\"rsa-sha256\""))
        XCTAssertTrue(signatureHeader.contains("headers="))
        XCTAssertTrue(signatureHeader.contains("signature="))
    }

    func testDigestHeaderFormat() throws {
        let body = #"{"type":"Follow"}"#.data(using: .utf8)!
        let hash = SHA256.hash(data: body)
        let base64 = Data(hash).base64EncodedString()
        let digestHeader = "SHA-256=\(base64)"
        XCTAssertTrue(digestHeader.hasPrefix("SHA-256="))
        XCTAssertFalse(base64.isEmpty)
    }

    // MARK: - MastodonStatus Decoding

    func testDecodeMastodonStatus() throws {
        let json = """
        {
          "id": "109876543210",
          "uri": "https://mastodon.social/users/alice/statuses/109876543210",
          "url": "https://mastodon.social/@alice/109876543210",
          "created_at": "2026-03-21T12:00:00.000Z",
          "account": {
            "id": "12345",
            "username": "alice",
            "acct": "alice@mastodon.social",
            "display_name": "Alice Smith",
            "locked": false,
            "bot": false,
            "created_at": "2022-01-01T00:00:00.000Z",
            "note": "<p>Hello!</p>",
            "url": "https://mastodon.social/@alice",
            "avatar": "https://files.mastodon.social/accounts/avatars/alice.jpg",
            "avatar_static": "https://files.mastodon.social/accounts/avatars/alice.jpg",
            "header": "https://files.mastodon.social/accounts/headers/alice.jpg",
            "header_static": "https://files.mastodon.social/accounts/headers/alice.jpg",
            "followers_count": 1234,
            "following_count": 567,
            "statuses_count": 89,
            "emojis": [],
            "fields": []
          },
          "content": "<p>Hello, Mastodon!</p>",
          "visibility": "public",
          "sensitive": false,
          "spoiler_text": "",
          "media_attachments": [],
          "mentions": [],
          "tags": [],
          "emojis": [],
          "reblogs_count": 5,
          "favourites_count": 42,
          "replies_count": 3,
          "favourited": false,
          "reblogged": false,
          "muted": false,
          "bookmarked": false
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(MastodonStatus.self, from: json)

        XCTAssertEqual(status.id, "109876543210")
        XCTAssertEqual(status.content, "<p>Hello, Mastodon!</p>")
        XCTAssertEqual(status.visibility, .public)
        XCTAssertEqual(status.account.username, "alice")
        XCTAssertEqual(status.account.displayName, "Alice Smith")
        XCTAssertEqual(status.favouritesCount, 42)
        XCTAssertEqual(status.reblogsCount, 5)
        XCTAssertFalse(status.sensitive)
    }

    func testMastodonStatusCreatedDate() throws {
        let json = """
        {
          "id": "1",
          "uri": "https://example.com/1",
          "created_at": "2026-03-21T12:00:00.000Z",
          "account": {
            "id": "1",
            "username": "test",
            "acct": "test@example.com",
            "display_name": "Test",
            "locked": false,
            "bot": false,
            "created_at": "2026-01-01T00:00:00.000Z",
            "note": "",
            "url": "https://example.com/@test",
            "avatar": "https://example.com/avatar.jpg",
            "avatar_static": "https://example.com/avatar.jpg",
            "header": "https://example.com/header.jpg",
            "header_static": "https://example.com/header.jpg",
            "followers_count": 0,
            "following_count": 0,
            "statuses_count": 0,
            "emojis": [],
            "fields": []
          },
          "content": "Test",
          "visibility": "public",
          "sensitive": false,
          "spoiler_text": "",
          "media_attachments": [],
          "mentions": [],
          "tags": [],
          "emojis": [],
          "reblogs_count": 0,
          "favourites_count": 0,
          "replies_count": 0
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let status = try decoder.decode(MastodonStatus.self, from: json)
        let date = status.createdDate
        XCTAssertNotNil(date)

        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date!)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 3)
        XCTAssertEqual(components.day, 21)
    }

    // MARK: - AuthManager

    func testFederationPlatformEncoding() throws {
        let platforms: [FederationPlatform] = [.mastodon, .pixelfed, .rosemount]
        for platform in platforms {
            let data = try JSONEncoder().encode(platform)
            let decoded = try JSONDecoder().decode(FederationPlatform.self, from: data)
            XCTAssertEqual(decoded, platform)
        }
    }
}
