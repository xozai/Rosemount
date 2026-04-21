// PushNotificationServiceTests.swift
// Rosemount
//
// Unit tests for PushNotificationService: deep-link routing from notification
// payloads, pending deep-link consumption, and DeepLink equatability.
// Swift 5.10 | iOS 17.0+
//
// Note: Tests that require APNs registration (requestAuthorization,
// handleDeviceToken) are not exercised here as they need a real device/simulator
// with a signed bundle. This file covers all pure-logic paths.

import XCTest
@testable import Rosemount

@MainActor
final class PushNotificationServiceTests: XCTestCase {

    private var service: PushNotificationService { .shared }

    override func setUp() async throws {
        try await super.setUp()
        // Clear any residual state from previous tests.
        _ = service.consumePendingDeepLink()
    }

    // MARK: - DeepLink Equatable

    func testDeepLinkProfileEquality() {
        XCTAssertEqual(DeepLink.profile(accountId: "1"), DeepLink.profile(accountId: "1"))
        XCTAssertNotEqual(DeepLink.profile(accountId: "1"), DeepLink.profile(accountId: "2"))
    }

    func testDeepLinkStatusEquality() {
        XCTAssertEqual(DeepLink.status(statusId: "s1"), DeepLink.status(statusId: "s1"))
        XCTAssertNotEqual(DeepLink.status(statusId: "s1"), DeepLink.status(statusId: "s2"))
    }

    func testDeepLinkConversationEquality() {
        XCTAssertEqual(DeepLink.conversation(conversationId: "c1"), DeepLink.conversation(conversationId: "c1"))
        XCTAssertNotEqual(DeepLink.conversation(conversationId: "c1"), DeepLink.conversation(conversationId: "c2"))
    }

    func testDeepLinkNotificationsEquality() {
        XCTAssertEqual(DeepLink.notifications, DeepLink.notifications)
    }

    func testDeepLinkCrossTypeInequality() {
        XCTAssertNotEqual(DeepLink.notifications, DeepLink.status(statusId: "1"))
        XCTAssertNotEqual(DeepLink.profile(accountId: "1"), DeepLink.status(statusId: "1"))
    }

    // MARK: - handleNotification: mention

    func testMentionWithStatusIdRoutesToStatus() {
        let userInfo: [AnyHashable: Any] = ["type": "mention", "status_id": "s123"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .status(statusId: "s123"))
    }

    func testMentionWithoutStatusIdFallsBackToProfile() {
        let userInfo: [AnyHashable: Any] = ["type": "mention", "account_id": "a1"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .profile(accountId: "a1"))
    }

    func testMentionWithNoIdsRoutesToNotifications() {
        let userInfo: [AnyHashable: Any] = ["type": "mention"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .notifications)
    }

    // MARK: - handleNotification: status / reblog / favourite / poll / update

    func testStatusTypeWithStatusIdRoutesToStatus() {
        for type in ["status", "reblog", "favourite", "poll", "update"] {
            let link = service.handleNotification(["type": type, "status_id": "s\(type)"])
            XCTAssertEqual(link, .status(statusId: "s\(type)"), "type: \(type)")
        }
    }

    // MARK: - handleNotification: follow

    func testFollowWithAccountIdRoutesToProfile() {
        let userInfo: [AnyHashable: Any] = ["type": "follow", "account_id": "a99"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .profile(accountId: "a99"))
    }

    func testFollowRequestWithAccountIdRoutesToProfile() {
        let userInfo: [AnyHashable: Any] = ["type": "follow_request", "account_id": "a88"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .profile(accountId: "a88"))
    }

    func testFollowWithoutAccountIdRoutesToNotifications() {
        let userInfo: [AnyHashable: Any] = ["type": "follow"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .notifications)
    }

    // MARK: - handleNotification: direct message

    func testDirectMessageWithConversationIdRoutesToConversation() {
        let userInfo: [AnyHashable: Any] = ["type": "direct", "conversation_id": "conv42"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .conversation(conversationId: "conv42"))
    }

    func testDirectMessageWithoutConversationIdRoutesToNotifications() {
        let userInfo: [AnyHashable: Any] = ["type": "direct"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .notifications)
    }

    // MARK: - handleNotification: unknown / missing type

    func testUnknownTypeRoutesToNotifications() {
        let userInfo: [AnyHashable: Any] = ["type": "some_future_type"]
        let link = service.handleNotification(userInfo)
        XCTAssertEqual(link, .notifications)
    }

    func testMissingTypeReturnsNil() {
        let link = service.handleNotification([:])
        XCTAssertNil(link)
    }

    // MARK: - pendingDeepLink state

    func testHandleNotificationSetsPendingDeepLink() {
        let userInfo: [AnyHashable: Any] = ["type": "follow", "account_id": "abc"]
        _ = service.handleNotification(userInfo)
        XCTAssertEqual(service.pendingDeepLink, .profile(accountId: "abc"))
    }

    // MARK: - consumePendingDeepLink

    func testConsumeClearsPendingDeepLink() {
        let userInfo: [AnyHashable: Any] = ["type": "mention", "status_id": "s1"]
        _ = service.handleNotification(userInfo)
        XCTAssertNotNil(service.pendingDeepLink)

        let consumed = service.consumePendingDeepLink()
        XCTAssertEqual(consumed, .status(statusId: "s1"))
        XCTAssertNil(service.pendingDeepLink, "pendingDeepLink should be nil after consumption")
    }

    func testConsumeWhenNilReturnsNil() {
        XCTAssertNil(service.consumePendingDeepLink())
    }

    func testConsumeIsIdempotent() {
        let userInfo: [AnyHashable: Any] = ["type": "follow", "account_id": "x"]
        _ = service.handleNotification(userInfo)
        _ = service.consumePendingDeepLink()
        XCTAssertNil(service.consumePendingDeepLink())
    }

    // MARK: - clearBadge

    func testClearBadgeDoesNotCrash() async {
        // Just verify the method completes without throwing — UNUserNotificationCenter
        // operations are no-ops in a test environment.
        await service.clearBadge()
    }
}
