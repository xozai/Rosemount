// ComposeViewModelTests.swift
// Rosemount
//
// Unit tests for ComposeViewModel and PollComposerViewModel.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class ComposeViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = ComposeViewModel()
        XCTAssertTrue(vm.content.isEmpty)
        XCTAssertEqual(vm.visibility, .public)
        XCTAssertFalse(vm.hasSpoilerText)
        XCTAssertTrue(vm.spoilerText.isEmpty)
        XCTAssertTrue(vm.attachments.isEmpty)
        XCTAssertFalse(vm.isPosting)
        XCTAssertFalse(vm.didPost)
        XCTAssertNil(vm.error)
        XCTAssertFalse(vm.isPollEnabled)
    }

    // MARK: - Character Count

    func testCharacterCountBodyOnly() {
        let vm = ComposeViewModel()
        vm.content = "Hello"
        XCTAssertEqual(vm.characterCount, 5)
        XCTAssertEqual(vm.remainingCharacters, 495)
    }

    func testCharacterCountIncludesReplyMention() {
        let vm = ComposeViewModel()
        vm.replyToMention = "@alice "
        vm.content = "hi"
        XCTAssertEqual(vm.characterCount, 9)   // 7 + 2
    }

    func testCharacterCountIncludesSpoilerWhenEnabled() {
        let vm = ComposeViewModel()
        vm.hasSpoilerText = true
        vm.spoilerText = "CW"
        vm.content = "body"
        XCTAssertEqual(vm.characterCount, 6)
    }

    func testCharacterCountIgnoresSpoilerWhenDisabled() {
        let vm = ComposeViewModel()
        vm.hasSpoilerText = false
        vm.spoilerText = "CW"
        vm.content = "body"
        XCTAssertEqual(vm.characterCount, 4)
    }

    // MARK: - canPost

    func testCanPostFalseWhenContentEmpty() {
        let vm = ComposeViewModel()
        XCTAssertFalse(vm.canPost)
    }

    func testCanPostTrueWithContent() {
        let vm = ComposeViewModel()
        vm.content = "Hello world"
        XCTAssertTrue(vm.canPost)
    }

    func testCanPostFalseWhenOverLimit() {
        let vm = ComposeViewModel()
        vm.content = String(repeating: "a", count: 501)
        XCTAssertFalse(vm.canPost)
    }

    func testCanPostFalseWhilePosting() {
        let vm = ComposeViewModel()
        vm.content = "Hello"
        vm.isPosting = true
        XCTAssertFalse(vm.canPost)
    }

    // MARK: - Poll canPost interaction

    func testCanPostFalseWhenPollEnabledButInvalid() {
        let vm = ComposeViewModel()
        vm.content = "Pick one"
        vm.isPollEnabled = true
        // Default PollComposerViewModel has two empty options — isValid is false
        XCTAssertFalse(vm.canPost)
    }

    func testCanPostTrueWhenPollEnabledAndValid() {
        let vm = ComposeViewModel()
        vm.content = "Pick one"
        vm.isPollEnabled = true
        vm.pollComposerViewModel.options[0].text = "Option A"
        vm.pollComposerViewModel.options[1].text = "Option B"
        XCTAssertTrue(vm.canPost)
    }

    // MARK: - attachPoll / removePoll

    func testAttachPollSetsIsPollEnabled() {
        let vm = ComposeViewModel()
        vm.attachPoll()
        XCTAssertTrue(vm.isPollEnabled)
    }

    func testAttachPollBlockedWhenMediaAttached() {
        let vm = ComposeViewModel()
        vm.attachments = [MastodonAttachment.makeStub()]
        vm.attachPoll()
        XCTAssertFalse(vm.isPollEnabled, "Cannot attach poll while media is present")
    }

    func testRemovePollClearsState() {
        let vm = ComposeViewModel()
        vm.attachPoll()
        vm.pollComposerViewModel.options[0].text = "yes"
        vm.pollComposerViewModel.options[1].text = "no"
        vm.removePoll()
        XCTAssertFalse(vm.isPollEnabled)
        XCTAssertTrue(vm.pollComposerViewModel.options[0].text.isEmpty)
    }

    // MARK: - discardDraft

    func testDiscardDraftResetsAllState() {
        let vm = ComposeViewModel()
        vm.content = "Hello"
        vm.hasSpoilerText = true
        vm.spoilerText = "cw"
        vm.visibility = .private
        vm.isPollEnabled = true
        vm.discardDraft()

        XCTAssertTrue(vm.content.isEmpty)
        XCTAssertFalse(vm.hasSpoilerText)
        XCTAssertTrue(vm.spoilerText.isEmpty)
        XCTAssertEqual(vm.visibility, .public)
        XCTAssertFalse(vm.isPollEnabled)
        XCTAssertFalse(vm.isPosting)
        XCTAssertFalse(vm.didPost)
        XCTAssertNil(vm.error)
    }

    // MARK: - setupReply

    func testSetupReplyPreFillsMention() {
        let vm = ComposeViewModel()
        let status = MastodonStatus.makeStub(id: "1", acct: "bob@mastodon.social")
        vm.setupReply(to: status)
        XCTAssertEqual(vm.inReplyToId, "1")
        XCTAssertEqual(vm.replyToMention, "@bob@mastodon.social ")
    }

    func testSetupReplyDirectVisibilityKeptDirect() {
        let vm = ComposeViewModel()
        let status = MastodonStatus.makeStub(id: "2", visibility: .direct)
        vm.setupReply(to: status)
        XCTAssertEqual(vm.visibility, .direct)
    }
}

// MARK: - PollComposerViewModel Tests

final class PollComposerViewModelTests: XCTestCase {

    func testInitialHasTwoOptions() {
        let vm = PollComposerViewModel()
        XCTAssertEqual(vm.options.count, 2)
    }

    func testCanAddOptionUpToFour() {
        let vm = PollComposerViewModel()
        XCTAssertTrue(vm.canAddOption)
        vm.addOption()
        vm.addOption()
        XCTAssertFalse(vm.canAddOption)
        vm.addOption()   // should be ignored
        XCTAssertEqual(vm.options.count, 4)
    }

    func testRemoveOptionReducesCount() {
        let vm = PollComposerViewModel()
        vm.addOption()   // now 3
        vm.removeOption(at: 0)
        XCTAssertEqual(vm.options.count, 2)
    }

    func testRemoveOptionDoesNotGoBelowTwo() {
        let vm = PollComposerViewModel()
        vm.removeOption(at: 0)   // attempt to go to 1
        XCTAssertEqual(vm.options.count, 2)
    }

    func testIsValidRequiresAllOptionsNonEmpty() {
        let vm = PollComposerViewModel()
        XCTAssertFalse(vm.isValid)
        vm.options[0].text = "Yes"
        XCTAssertFalse(vm.isValid)
        vm.options[1].text = "No"
        XCTAssertTrue(vm.isValid)
    }

    func testApiPayloadContainsPollFields() {
        let vm = PollComposerViewModel()
        vm.options[0].text = "A"
        vm.options[1].text = "B"
        vm.expiryDuration = .oneDay
        vm.isMultipleChoice = true

        let payload = vm.apiPayload
        let options = payload["options"] as? [String]
        XCTAssertEqual(options, ["A", "B"])
        XCTAssertEqual(payload["expires_in"] as? Int, 86400)
        XCTAssertEqual(payload["multiple"] as? Bool, true)
    }
}

// MARK: - Stubs

private extension MastodonAttachment {
    static func makeStub() -> MastodonAttachment {
        let json = """
        {"id":"att-1","type":"image","url":"https://example.com/img.jpg",
         "preview_url":null,"description":null}
        """.data(using: .utf8)!
        return try! JSONDecoder.mastodon.decode(MastodonAttachment.self, from: json)
    }
}

private extension MastodonStatus {
    static func makeStub(
        id: String = "0",
        acct: String = "user@mastodon.social",
        visibility: MastodonVisibility = .public
    ) -> MastodonStatus {
        let json = """
        {
          "id":"\(id)",
          "uri":"https://mastodon.social/statuses/\(id)",
          "url":null,
          "created_at":"2025-01-01T00:00:00Z",
          "account":{"id":"acct-\(id)","username":"\(acct)","acct":"\(acct)",
            "display_name":"\(acct)","note":"","avatar":null,"header":null,
            "followers_count":0,"following_count":0,"statuses_count":0,"locked":false,"fields":[]},
          "content":"stub",
          "visibility":"\(visibility.rawValue)",
          "sensitive":false,
          "spoiler_text":"",
          "media_attachments":[],
          "mentions":[],"tags":[],"emojis":[],
          "reblogs_count":0,"favourites_count":0,"replies_count":0,
          "reblog":null,"poll":null,"card":null
        }
        """.data(using: .utf8)!
        return try! JSONDecoder.mastodon.decode(MastodonStatus.self, from: json)
    }
}
