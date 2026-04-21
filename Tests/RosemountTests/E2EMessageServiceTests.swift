// E2EMessageServiceTests.swift
// Rosemount
//
// Unit tests for E2EMessageService and related helpers.
// Tests: identity key generation, isEncrypted/isCompatMode detection,
// ensureIdentityKey idempotency, and error descriptions.
// Swift 5.10 | iOS 17.0+

import XCTest
import CryptoKit
@testable import Rosemount

final class E2EMessageServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService() -> E2EMessageService {
        let cred = AccountCredential(
            handle: "alice@mastodon.social",
            instanceURL: URL(string: "https://mastodon.social")!,
            accessToken: "test-token",
            tokenType: "Bearer",
            scope: "read write",
            platform: .mastodon
        )
        return E2EMessageService(credential: cred)
    }

    // MARK: - E2EError descriptions

    func testE2EErrorDescriptionsAreNonEmpty() {
        let cases: [E2EError] = [.noSession, .encryptionFailed, .decryptionFailed, .keyNotFound, .signatureFailed]
        for error in cases {
            let desc = error.errorDescription
            XCTAssertNotNil(desc, "errorDescription should not be nil for \(error)")
            XCTAssertFalse(desc!.isEmpty, "errorDescription should not be empty for \(error)")
        }
    }

    // MARK: - Encrypted prefix constants

    func testEncryptedPrefixIsNonEmpty() {
        XCTAssertFalse(E2EMessageService.encryptedPrefix.isEmpty)
    }

    func testEncryptedCompatPrefixIsNonEmpty() {
        XCTAssertFalse(E2EMessageService.encryptedCompatPrefix.isEmpty)
    }

    func testEncryptedPrefixDiffersFromCompatPrefix() {
        XCTAssertNotEqual(E2EMessageService.encryptedPrefix, E2EMessageService.encryptedCompatPrefix)
    }

    // MARK: - isEncrypted

    func testIsEncryptedReturnsTrueForEncryptedPrefix() async {
        let service = makeService()
        let status = makeStatus(content: E2EMessageService.encryptedPrefix + "abc123")
        let result = await service.isEncrypted(status)
        XCTAssertTrue(result)
    }

    func testIsEncryptedReturnsTrueForCompatPrefix() async {
        let service = makeService()
        let status = makeStatus(content: E2EMessageService.encryptedCompatPrefix + "abc123")
        let result = await service.isEncrypted(status)
        XCTAssertTrue(result)
    }

    func testIsEncryptedReturnsFalseForPlainText() async {
        let service = makeService()
        let status = makeStatus(content: "Hello, this is plain text.")
        let result = await service.isEncrypted(status)
        XCTAssertFalse(result)
    }

    func testIsEncryptedReturnsFalseForEmptyContent() async {
        let service = makeService()
        let status = makeStatus(content: "")
        let result = await service.isEncrypted(status)
        XCTAssertFalse(result)
    }

    // MARK: - isCompatMode

    func testIsCompatModeTrueForCompatPrefix() async {
        let service = makeService()
        let status = makeStatus(content: E2EMessageService.encryptedCompatPrefix + "data")
        let result = await service.isCompatMode(status)
        XCTAssertTrue(result)
    }

    func testIsCompatModeFalseForFullEncryptedPrefix() async {
        let service = makeService()
        let status = makeStatus(content: E2EMessageService.encryptedPrefix + "data")
        let result = await service.isCompatMode(status)
        XCTAssertFalse(result)
    }

    func testIsCompatModeFalseForPlainText() async {
        let service = makeService()
        let status = makeStatus(content: "plain text")
        let result = await service.isCompatMode(status)
        XCTAssertFalse(result)
    }

    // MARK: - ensureIdentityKey

    func testEnsureIdentityKeyGeneratesKeyPair() async throws {
        let service = makeService()
        // Key pair is nil before first call
        let beforeKey = await service.localIdentityKeyPair
        XCTAssertNil(beforeKey)

        try await service.ensureIdentityKey()

        let afterKey = await service.localIdentityKeyPair
        XCTAssertNotNil(afterKey, "ensureIdentityKey should generate a key pair")
    }

    func testEnsureIdentityKeyIsIdempotent() async throws {
        let service = makeService()
        try await service.ensureIdentityKey()
        let firstKey = await service.localIdentityKeyPair

        try await service.ensureIdentityKey()
        let secondKey = await service.localIdentityKeyPair

        XCTAssertNotNil(firstKey)
        XCTAssertNotNil(secondKey)
        // The same key pair should be reused (compare raw public key bytes)
        XCTAssertEqual(
            firstKey?.publicKey.rawRepresentation,
            secondKey?.publicKey.rawRepresentation,
            "ensureIdentityKey should reuse an existing key pair"
        )
    }
}

// MARK: - Helpers

private func makeStatus(content: String) -> MastodonStatus {
    // Escape content for JSON embedding
    let escaped = content
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
    let json = """
    {
      "id":"test-status","uri":"https://mastodon.social/statuses/1",
      "url":null,"created_at":"2025-01-01T00:00:00Z",
      "account":{"id":"acct-1","username":"alice","acct":"alice@mastodon.social",
        "display_name":"Alice","note":"","avatar":null,"header":null,
        "followers_count":0,"following_count":0,"statuses_count":0,"locked":false,"fields":[]},
      "content":"\(escaped)",
      "visibility":"direct","sensitive":false,"spoiler_text":"",
      "media_attachments":[],"mentions":[],"tags":[],"emojis":[],
      "reblogs_count":0,"favourites_count":0,"replies_count":0,
      "reblog":null,"poll":null,"card":null
    }
    """.data(using: .utf8)!
    return try! JSONDecoder.mastodon.decode(MastodonStatus.self, from: json)
}

