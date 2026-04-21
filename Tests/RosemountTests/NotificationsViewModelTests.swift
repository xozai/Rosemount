// NotificationsViewModelTests.swift
// Rosemount
//
// Unit tests for NotificationsViewModel and NotificationFilter.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class NotificationsViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = NotificationsViewModel()
        XCTAssertTrue(vm.notifications.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasMore)
        XCTAssertEqual(vm.filter, .all)
        XCTAssertTrue(vm.filteredNotifications.isEmpty)
    }

    // MARK: - filteredNotifications

    func testFilterAllIncludesEverything() {
        let vm = NotificationsViewModel()
        vm.notifications = [
            makeNotification(id: "1", type: .mention),
            makeNotification(id: "2", type: .follow),
            makeNotification(id: "3", type: .favourite),
            makeNotification(id: "4", type: .reblog),
        ]
        vm.filter = .all
        XCTAssertEqual(vm.filteredNotifications.count, 4)
    }

    func testFilterMentionsExcludesOthers() {
        let vm = NotificationsViewModel()
        vm.notifications = [
            makeNotification(id: "1", type: .mention),
            makeNotification(id: "2", type: .follow),
            makeNotification(id: "3", type: .favourite),
        ]
        vm.filter = .mentions
        XCTAssertEqual(vm.filteredNotifications.count, 1)
        XCTAssertEqual(vm.filteredNotifications.first?.type, .mention)
    }

    func testFilterFollowsIncludesFollowRequest() {
        let vm = NotificationsViewModel()
        vm.notifications = [
            makeNotification(id: "1", type: .follow),
            makeNotification(id: "2", type: .followRequest),
            makeNotification(id: "3", type: .mention),
        ]
        vm.filter = .follows
        XCTAssertEqual(vm.filteredNotifications.count, 2)
    }

    func testFilterBoostsShowsOnlyReblogs() {
        let vm = NotificationsViewModel()
        vm.notifications = [
            makeNotification(id: "1", type: .reblog),
            makeNotification(id: "2", type: .mention),
        ]
        vm.filter = .boosts
        XCTAssertEqual(vm.filteredNotifications.count, 1)
        XCTAssertEqual(vm.filteredNotifications.first?.id, "1")
    }

    func testFilterFavouritesShowsOnlyFavourites() {
        let vm = NotificationsViewModel()
        vm.notifications = [
            makeNotification(id: "1", type: .favourite),
            makeNotification(id: "2", type: .reblog),
        ]
        vm.filter = .favourites
        XCTAssertEqual(vm.filteredNotifications.count, 1)
        XCTAssertEqual(vm.filteredNotifications.first?.id, "1")
    }

    func testFilteredNotificationsRespectsActiveFilter() {
        let vm = NotificationsViewModel()
        vm.notifications = [makeNotification(id: "1", type: .mention)]
        vm.filter = .favourites
        XCTAssertTrue(vm.filteredNotifications.isEmpty)
    }

    // MARK: - NotificationFilter properties

    func testFilterTitlesAreNonEmpty() {
        for filter in NotificationFilter.allCases {
            XCTAssertFalse(filter.title.isEmpty)
        }
    }

    func testFilterIdMatchesRawValue() {
        for filter in NotificationFilter.allCases {
            XCTAssertEqual(filter.id, filter.rawValue)
        }
    }

    // MARK: - NotificationFilter.includes

    func testIncludesAllAlwaysTrue() {
        let notif = makeNotification(id: "x", type: .poll)
        XCTAssertTrue(NotificationFilter.all.includes(notif))
    }

    func testIncludesMentionOnlyForMention() {
        XCTAssertTrue(NotificationFilter.mentions.includes(makeNotification(id: "1", type: .mention)))
        XCTAssertFalse(NotificationFilter.mentions.includes(makeNotification(id: "2", type: .follow)))
    }

    func testIncludesFollowsForBothFollowTypes() {
        XCTAssertTrue(NotificationFilter.follows.includes(makeNotification(id: "1", type: .follow)))
        XCTAssertTrue(NotificationFilter.follows.includes(makeNotification(id: "2", type: .followRequest)))
        XCTAssertFalse(NotificationFilter.follows.includes(makeNotification(id: "3", type: .favourite)))
    }

    // MARK: - Guards (no network required)

    func testRefreshNoopsWhenAlreadyLoading() async {
        let vm = NotificationsViewModel()
        vm.isLoading = true
        await vm.refresh()   // no client → returns immediately; isLoading stays true
        XCTAssertTrue(vm.isLoading)
    }

    func testLoadMoreNoopsWhenHasMoreFalse() async {
        let vm = NotificationsViewModel()
        vm.hasMore = false
        await vm.loadMore()
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testLoadMoreNoopsWhenAlreadyLoadingMore() async {
        let vm = NotificationsViewModel()
        vm.isLoadingMore = true
        await vm.loadMore()
        // No client → guard trips; isLoadingMore unchanged
        XCTAssertTrue(vm.isLoadingMore)
    }

    func testLoadMoreNoopsWithoutClient() async {
        let vm = NotificationsViewModel()
        await vm.loadMore()
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.error)
    }
}

// MARK: - Helpers

private func makeNotification(
    id: String,
    type: MastodonNotificationType
) -> MastodonNotification {
    MastodonNotification(
        id: id,
        type: type,
        createdAt: "2025-01-01T00:00:00Z",
        account: makeAccount(id: "acct-\(id)"),
        status: nil
    )
}

private func makeAccount(id: String) -> MastodonAccount {
    MastodonAccount(
        id: id,
        username: "user\(id)",
        acct: "user\(id)@mastodon.social",
        displayName: "User \(id)",
        locked: false,
        bot: false,
        createdAt: "2024-01-01T00:00:00Z",
        note: "",
        url: "https://mastodon.social/@user\(id)",
        avatar: "",
        avatarStatic: "",
        header: "",
        headerStatic: "",
        followersCount: 0,
        followingCount: 0,
        statusesCount: 0,
        emojis: [],
        fields: []
    )
}
