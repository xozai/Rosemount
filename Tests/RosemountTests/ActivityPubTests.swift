import XCTest
@testable import Rosemount

final class ActivityPubTests: XCTestCase {

    // MARK: - APActor Decoding

    func testDecodePersonActor() throws {
        let json = """
        {
          "@context": [
            "https://www.w3.org/ns/activitystreams",
            "https://w3id.org/security/v1"
          ],
          "id": "https://mastodon.social/users/testuser",
          "type": "Person",
          "preferredUsername": "testuser",
          "name": "Test User",
          "summary": "<p>Hello world</p>",
          "url": "https://mastodon.social/@testuser",
          "inbox": "https://mastodon.social/users/testuser/inbox",
          "outbox": "https://mastodon.social/users/testuser/outbox",
          "followers": "https://mastodon.social/users/testuser/followers",
          "following": "https://mastodon.social/users/testuser/following",
          "publicKey": {
            "id": "https://mastodon.social/users/testuser#main-key",
            "owner": "https://mastodon.social/users/testuser",
            "publicKeyPem": "-----BEGIN PUBLIC KEY-----\\nMIIBIjANBgkq\\n-----END PUBLIC KEY-----"
          },
          "manuallyApprovesFollowers": false,
          "discoverable": true
        }
        """.data(using: .utf8)!

        let actor = try JSONDecoder().decode(APActor.self, from: json)
        XCTAssertEqual(actor.id, "https://mastodon.social/users/testuser")
        XCTAssertEqual(actor.type, .person)
        XCTAssertEqual(actor.preferredUsername, "testuser")
        XCTAssertEqual(actor.name, "Test User")
        XCTAssertEqual(actor.inbox, "https://mastodon.social/users/testuser/inbox")
        XCTAssertEqual(actor.publicKey?.owner, "https://mastodon.social/users/testuser")
        XCTAssertFalse(actor.manuallyApprovesFollowers ?? false)
        XCTAssertTrue(actor.discoverable ?? false)
    }

    func testDecodeActorWithStringContext() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://example.com/users/alice",
          "type": "Person",
          "preferredUsername": "alice",
          "inbox": "https://example.com/users/alice/inbox",
          "outbox": "https://example.com/users/alice/outbox",
          "followers": "https://example.com/users/alice/followers",
          "following": "https://example.com/users/alice/following"
        }
        """.data(using: .utf8)!

        let actor = try JSONDecoder().decode(APActor.self, from: json)
        XCTAssertEqual(actor.preferredUsername, "alice")
        XCTAssertEqual(actor.instanceHost, "example.com")
    }

    func testActorHandle() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://mastodon.social/users/bob",
          "type": "Person",
          "preferredUsername": "bob",
          "inbox": "https://mastodon.social/users/bob/inbox",
          "outbox": "https://mastodon.social/users/bob/outbox",
          "followers": "https://mastodon.social/users/bob/followers",
          "following": "https://mastodon.social/users/bob/following"
        }
        """.data(using: .utf8)!

        let actor = try JSONDecoder().decode(APActor.self, from: json)
        XCTAssertEqual(actor.handle, "@bob@mastodon.social")
    }

    func testDecodeGroupActor() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://rosemount.social/communities/softball-league",
          "type": "Group",
          "preferredUsername": "softball-league",
          "name": "Springfield Softball League",
          "inbox": "https://rosemount.social/communities/softball-league/inbox",
          "outbox": "https://rosemount.social/communities/softball-league/outbox",
          "followers": "https://rosemount.social/communities/softball-league/followers",
          "following": "https://rosemount.social/communities/softball-league/following"
        }
        """.data(using: .utf8)!

        let actor = try JSONDecoder().decode(APActor.self, from: json)
        XCTAssertEqual(actor.type, .group)
        XCTAssertEqual(actor.name, "Springfield Softball League")
    }

    // MARK: - APActor Encoding

    func testEncodeActor() throws {
        let actor = APActor(
            context: nil,
            id: "https://rosemount.social/users/alice",
            type: .person,
            preferredUsername: "alice",
            name: "Alice Smith",
            summary: "Hello from Rosemount!",
            url: "https://rosemount.social/@alice",
            inbox: "https://rosemount.social/users/alice/inbox",
            outbox: "https://rosemount.social/users/alice/outbox",
            followers: "https://rosemount.social/users/alice/followers",
            following: "https://rosemount.social/users/alice/following",
            publicKey: nil,
            icon: nil,
            image: nil,
            endpoints: APEndpoints(sharedInbox: "https://rosemount.social/inbox"),
            manuallyApprovesFollowers: false,
            discoverable: true,
            published: nil
        )

        let data = try JSONEncoder().encode(actor)
        let decoded = try JSONDecoder().decode(APActor.self, from: data)
        XCTAssertEqual(decoded.id, actor.id)
        XCTAssertEqual(decoded.preferredUsername, actor.preferredUsername)
        XCTAssertEqual(decoded.type, actor.type)
    }

    // MARK: - APNote Decoding

    func testDecodeNote() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://mastodon.social/users/testuser/statuses/123",
          "type": "Note",
          "attributedTo": "https://mastodon.social/users/testuser",
          "content": "<p>Hello, fediverse!</p>",
          "to": ["https://www.w3.org/ns/activitystreams#Public"],
          "cc": ["https://mastodon.social/users/testuser/followers"],
          "published": "2026-03-21T12:00:00Z",
          "url": "https://mastodon.social/@testuser/123",
          "attachment": [],
          "tag": [
            { "type": "Hashtag", "href": "https://mastodon.social/tags/fediverse", "name": "#fediverse" }
          ]
        }
        """.data(using: .utf8)!

        let note = try JSONDecoder().decode(APNote.self, from: json)
        XCTAssertEqual(note.id, "https://mastodon.social/users/testuser/statuses/123")
        XCTAssertEqual(note.type, "Note")
        XCTAssertEqual(note.content, "<p>Hello, fediverse!</p>")
        XCTAssertFalse(note.sensitive ?? false)
        XCTAssertEqual(note.tag?.first?.name, "#fediverse")
    }

    // MARK: - APActivity Decoding

    func testDecodeCreateActivity() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://mastodon.social/users/testuser/statuses/123/activity",
          "type": "Create",
          "actor": "https://mastodon.social/users/testuser",
          "to": ["https://www.w3.org/ns/activitystreams#Public"],
          "cc": ["https://mastodon.social/users/testuser/followers"],
          "object": {
            "id": "https://mastodon.social/users/testuser/statuses/123",
            "type": "Note",
            "attributedTo": "https://mastodon.social/users/testuser",
            "content": "<p>Hello!</p>",
            "to": ["https://www.w3.org/ns/activitystreams#Public"],
            "cc": [],
            "published": "2026-03-21T12:00:00Z"
          },
          "published": "2026-03-21T12:00:00Z"
        }
        """.data(using: .utf8)!

        let activity = try JSONDecoder().decode(APActivity.self, from: json)
        XCTAssertEqual(activity.type, .create)
        if case .string(let actorId) = activity.actor {
            XCTAssertEqual(actorId, "https://mastodon.social/users/testuser")
        } else {
            XCTFail("Expected actor to be a string ID")
        }
        if case .note(let note) = activity.object {
            XCTAssertEqual(note.content, "<p>Hello!</p>")
        } else {
            XCTFail("Expected object to be a Note")
        }
    }

    func testDecodeFollowActivity() throws {
        let json = """
        {
          "@context": "https://www.w3.org/ns/activitystreams",
          "id": "https://mastodon.social/users/alice#follows/1",
          "type": "Follow",
          "actor": "https://mastodon.social/users/alice",
          "object": "https://rosemount.social/users/bob"
        }
        """.data(using: .utf8)!

        let activity = try JSONDecoder().decode(APActivity.self, from: json)
        XCTAssertEqual(activity.type, .follow)
        if case .string(let objectId) = activity.object {
            XCTAssertEqual(objectId, "https://rosemount.social/users/bob")
        } else {
            XCTFail("Expected object to be a string ID for Follow activity")
        }
    }

    // MARK: - APVisibility

    func testPublicVisibility() throws {
        let note = APNote(
            id: "https://example.com/notes/1",
            type: "Note",
            attributedTo: "https://example.com/users/alice",
            content: "Test",
            contentMap: nil,
            summary: nil,
            sensitive: false,
            to: ["https://www.w3.org/ns/activitystreams#Public"],
            cc: ["https://example.com/users/alice/followers"],
            inReplyTo: nil,
            published: "2026-03-21T12:00:00Z",
            url: nil,
            attachment: nil,
            tag: nil,
            replies: nil
        )
        XCTAssertEqual(note.visibility, .public)
    }

    func testDirectVisibility() throws {
        let note = APNote(
            id: "https://example.com/notes/2",
            type: "Note",
            attributedTo: "https://example.com/users/alice",
            content: "Direct message",
            contentMap: nil,
            summary: nil,
            sensitive: false,
            to: ["https://example.com/users/bob"],
            cc: [],
            inReplyTo: nil,
            published: "2026-03-21T12:00:00Z",
            url: nil,
            attachment: nil,
            tag: nil,
            replies: nil
        )
        XCTAssertEqual(note.visibility, .direct)
    }
}
