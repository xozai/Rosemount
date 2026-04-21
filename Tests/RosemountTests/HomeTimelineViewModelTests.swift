// HomeTimelineViewModelTests.swift
// Rosemount
//
// Unit tests for HomeTimelineViewModel.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class HomeTimelineViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = HomeTimelineViewModel()
        XCTAssertTrue(vm.statuses.isEmpty)
        XCTAssertEqual(vm.feedType, .home)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasMore)
        XCTAssertFalse(vm.isDemoMode)
    }

    // MARK: - Demo Mode

    func testSetupWithDemoCredentialEnablesDemoMode() {
        let vm = HomeTimelineViewModel()
        let demo = AccountCredential.makeDemo()
        vm.setup(with: demo)
        XCTAssertTrue(vm.isDemoMode)
    }

    func testSetupWithRegularCredentialLeavesDemoModeFalse() {
        let vm = HomeTimelineViewModel()
        let cred = AccountCredential.makeFake(handle: "alice@mastodon.social")
        vm.setup(with: cred)
        XCTAssertFalse(vm.isDemoMode)
    }

    func testRefreshLoadsDemoStatuses() async {
        let vm = HomeTimelineViewModel()
        vm.setup(with: .makeDemo())
        await vm.refresh()
        XCTAssertFalse(vm.statuses.isEmpty, "Demo mode should load stub statuses")
        XCTAssertFalse(vm.isLoading)
    }

    // MARK: - Setup Resets State

    func testSetupResetsStatuses() async {
        let vm = HomeTimelineViewModel()
        vm.setup(with: .makeDemo())
        await vm.refresh()
        XCTAssertFalse(vm.statuses.isEmpty)

        // Re-setup resets everything
        vm.setup(with: .makeDemo())
        XCTAssertTrue(vm.statuses.isEmpty)
        XCTAssertTrue(vm.hasMore)
        XCTAssertNil(vm.error)
    }

    // MARK: - Feed Type

    func testSwitchFeedChangesFeedType() async {
        let vm = HomeTimelineViewModel()
        vm.setup(with: .makeDemo())
        XCTAssertEqual(vm.feedType, .home)
        await vm.switchFeed(to: .local)
        XCTAssertEqual(vm.feedType, .local)
    }

    func testSwitchFeedToSameTypeIsNoop() async {
        let vm = HomeTimelineViewModel()
        vm.setup(with: .makeDemo())
        await vm.refresh()
        let countBefore = vm.statuses.count
        await vm.switchFeed(to: .home)   // same type — should not reload
        XCTAssertEqual(vm.statuses.count, countBefore)
    }

    // MARK: - FeedType Icon

    func testFeedTypeIconsAreNonEmpty() {
        for type in FeedType.allCases {
            XCTAssertFalse(type.icon.isEmpty, "\(type) icon should be non-empty")
        }
    }
}

// MARK: - AccountCredential test helpers

private extension AccountCredential {
    static func makeDemo() -> AccountCredential {
        AccountCredential(
            handle: "app-review-demo",
            instanceURL: URL(string: "https://rosemount-review.local")!,
            accessToken: "demo-token",
            tokenType: "Bearer",
            scope: "read write",
            platform: .mastodon
        )
    }

    static func makeFake(handle: String) -> AccountCredential {
        AccountCredential(
            handle: handle,
            instanceURL: URL(string: "https://mastodon.social")!,
            accessToken: "fake-token",
            tokenType: "Bearer",
            scope: "read write",
            platform: .mastodon
        )
    }
}
