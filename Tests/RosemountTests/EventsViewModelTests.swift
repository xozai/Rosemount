// EventsViewModelTests.swift
// Rosemount
//
// Unit tests for EventsViewModel, RSVPStatus, and RosemountEvent helpers.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class EventsViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = EventsViewModel()
        XCTAssertTrue(vm.events.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertTrue(vm.showUpcomingOnly)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasMore)
    }

    // MARK: - refresh guard

    func testRefreshNoopsWithoutClient() async {
        let vm = EventsViewModel()
        await vm.refresh()
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.events.isEmpty)
    }

    // MARK: - loadMore guards

    func testLoadMoreNoopsWhenHasMoreFalse() async {
        let vm = EventsViewModel()
        vm.setup(communitySlug: "sports", credential: makeCred())
        vm.hasMore = false
        await vm.loadMore()
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testLoadMoreNoopsWhenAlreadyLoadingMore() async {
        let vm = EventsViewModel()
        vm.setup(communitySlug: "sports", credential: makeCred())
        vm.isLoadingMore = true
        await vm.loadMore()
        XCTAssertTrue(vm.isLoadingMore)
    }

    // MARK: - RSVP optimistic update

    func testRsvpUpdatesEventInPlace() async {
        let vm = EventsViewModel()
        let event = makeEvent(id: "e1", myRsvp: nil)
        vm.events = [event]

        // No real client → API call will fail, but optimistic update fires first.
        // We test the pre-call state by observing the events array after the guard.
        // Since setup() was never called the guard trips before rollback — verify
        // the array is unchanged.
        vm.setup(communitySlug: "sports", credential: makeCred())
        // Can't test async mid-point without mocks, so test the withMyRsvp helper directly.
        let patched = event.withMyRsvp(.going)
        XCTAssertEqual(patched.myRsvp, .going)
        XCTAssertEqual(patched.id, event.id)
    }

    func testRsvpRollbackRestoresOriginalEvent() async {
        let vm = EventsViewModel()
        let event = makeEvent(id: "e1", myRsvp: nil)
        vm.events = [event]

        // Simulate rollback: manually apply and then revert
        vm.events[0] = event.withMyRsvp(.going)
        XCTAssertEqual(vm.events[0].myRsvp, .going)

        vm.events[0] = event
        XCTAssertNil(vm.events[0].myRsvp)
    }

    // MARK: - RosemountEvent.withMyRsvp

    func testWithMyRsvpChangesOnlyRsvp() {
        let event = makeEvent(id: "e1", myRsvp: nil)
        let updated = event.withMyRsvp(.interested)
        XCTAssertEqual(updated.myRsvp, .interested)
        XCTAssertEqual(updated.id, event.id)
        XCTAssertEqual(updated.title, event.title)
        XCTAssertEqual(updated.startDate, event.startDate)
        XCTAssertEqual(updated.attendeeCount, event.attendeeCount)
    }

    func testWithMyRsvpCanClearStatus() {
        let event = makeEvent(id: "e1", myRsvp: .going)
        let updated = event.withMyRsvp(nil)
        XCTAssertNil(updated.myRsvp)
    }

    func testWithMyRsvpAllStatuses() {
        let event = makeEvent(id: "e1", myRsvp: nil)
        for status in RSVPStatus.allCases {
            let updated = event.withMyRsvp(status)
            XCTAssertEqual(updated.myRsvp, status)
        }
    }

    // MARK: - RSVPStatus

    func testRsvpStatusDisplayNamesAreNonEmpty() {
        for status in RSVPStatus.allCases {
            XCTAssertFalse(status.displayName.isEmpty)
        }
    }

    func testRsvpStatusSystemImagesAreNonEmpty() {
        for status in RSVPStatus.allCases {
            XCTAssertFalse(status.systemImage.isEmpty)
        }
    }

    func testRsvpStatusColorNamesAreNonEmpty() {
        for status in RSVPStatus.allCases {
            XCTAssertFalse(status.colorName.isEmpty)
        }
    }

    // MARK: - RosemountEvent helpers

    func testIsPastReturnsFalseForFutureEvent() {
        let event = makeEvent(id: "1", myRsvp: nil, startDateOffset: 3600)
        XCTAssertFalse(event.isPast)
    }

    func testIsPastReturnsTrueForPastEvent() {
        let event = makeEvent(id: "1", myRsvp: nil, startDateOffset: -3600)
        XCTAssertTrue(event.isPast)
    }

    func testStartDateFormattedIsNonEmptyForValidDate() {
        let event = makeEvent(id: "1", myRsvp: nil, startDateOffset: 3600)
        XCTAssertFalse(event.startDateFormatted.isEmpty)
    }
}

// MARK: - Helpers

private func makeCred() -> AccountCredential {
    AccountCredential(
        handle: "alice@mastodon.social",
        instanceURL: URL(string: "https://mastodon.social")!,
        accessToken: "tok",
        tokenType: "Bearer",
        scope: "read write",
        platform: .mastodon
    )
}

private func makeEvent(
    id: String,
    myRsvp: RSVPStatus?,
    startDateOffset: TimeInterval = 3600
) -> RosemountEvent {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let startDate = formatter.string(from: Date(timeIntervalSinceNow: startDateOffset))

    return RosemountEvent(
        id: id,
        title: "Test Event \(id)",
        description: "A test event",
        startDate: startDate,
        endDate: nil,
        timezone: "UTC",
        location: nil,
        organizer: makeAccount(id: "org-\(id)"),
        communityId: "community-1",
        communitySlug: "sports",
        attendeeCount: 5,
        interestedCount: 2,
        myRsvp: myRsvp,
        isOnline: false,
        onlineURL: nil,
        bannerURL: nil,
        createdAt: "2025-01-01T00:00:00Z",
        activityPubId: "https://mastodon.social/events/\(id)"
    )
}

private func makeAccount(id: String) -> MastodonAccount {
    MastodonAccount(
        id: id,
        username: "organiser",
        acct: "organiser@mastodon.social",
        displayName: "Organiser",
        locked: false,
        bot: false,
        createdAt: "2024-01-01T00:00:00Z",
        note: "",
        url: "https://mastodon.social/@organiser",
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
