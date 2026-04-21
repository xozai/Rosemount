// CommunitiesViewModelTests.swift
// Rosemount
//
// Unit tests for CommunitiesViewModel and related types.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class CommunitiesViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = CommunitiesViewModel()
        XCTAssertTrue(vm.joinedCommunities.isEmpty)
        XCTAssertTrue(vm.discoveredCommunities.isEmpty)
        XCTAssertTrue(vm.searchQuery.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isSearching)
        XCTAssertNil(vm.error)
        XCTAssertEqual(vm.selectedTab, .joined)
    }

    // MARK: - setup resets state

    func testSetupResetsArrays() {
        let vm = CommunitiesViewModel()
        vm.joinedCommunities = [makeCommunity(id: "1", slug: "c1", isMember: true)]
        vm.discoveredCommunities = [makeCommunity(id: "2", slug: "c2", isMember: false)]
        vm.searchQuery = "cats"
        vm.error = URLError(.notConnectedToInternet)

        vm.setup(with: makeCred())

        XCTAssertTrue(vm.joinedCommunities.isEmpty)
        XCTAssertTrue(vm.discoveredCommunities.isEmpty)
        XCTAssertTrue(vm.searchQuery.isEmpty)
        XCTAssertNil(vm.error)
    }

    // MARK: - CommunityTab

    func testCommunityTabTitlesAreNonEmpty() {
        for tab in CommunityTab.allCases {
            XCTAssertFalse(tab.title.isEmpty)
        }
    }

    func testCommunityTabIdMatchesRawValue() {
        for tab in CommunityTab.allCases {
            XCTAssertEqual(tab.id, tab.rawValue)
        }
    }

    func testCommunityTabJoinedIsDefault() {
        XCTAssertEqual(CommunityTab.joined.rawValue, 0)
        XCTAssertEqual(CommunityTab.discover.rawValue, 1)
    }

    // MARK: - CommunityRole

    func testCommunityRoleDisplayNamesAreNonEmpty() {
        for role in CommunityRole.allCases {
            XCTAssertFalse(role.displayName.isEmpty)
        }
    }

    func testCommunityRoleSystemImagesAreNonEmpty() {
        for role in CommunityRole.allCases {
            XCTAssertFalse(role.systemImage.isEmpty)
        }
    }

    // MARK: - refresh guard

    func testRefreshNoopsWithoutClient() async {
        let vm = CommunitiesViewModel()
        await vm.refresh()
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.joinedCommunities.isEmpty)
    }

    func testRefreshNoopsWhenAlreadyLoading() async {
        let vm = CommunitiesViewModel()
        vm.setup(with: makeCred())
        vm.isLoading = true
        await vm.refresh()
        XCTAssertTrue(vm.isLoading)   // still true, didn't reset
    }

    // MARK: - join / leave guards

    func testJoinNoopsWithoutClient() async {
        let vm = CommunitiesViewModel()
        let community = makeCommunity(id: "1", slug: "cats", isMember: false)
        vm.discoveredCommunities = [community]
        await vm.join(community)
        XCTAssertTrue(vm.joinedCommunities.isEmpty)
    }

    func testLeaveNoopsWithoutClient() async {
        let vm = CommunitiesViewModel()
        let community = makeCommunity(id: "1", slug: "cats", isMember: true)
        vm.joinedCommunities = [community]
        await vm.leave(community)
        // No client → guard trips before any changes
        XCTAssertEqual(vm.joinedCommunities.count, 1)
    }

    // MARK: - search guard

    func testSearchNoopsWithoutClientWhenQueryNonEmpty() async {
        let vm = CommunitiesViewModel()
        vm.searchQuery = "swift"
        await vm.search()
        XCTAssertFalse(vm.isSearching)
    }

    // MARK: - RosemountCommunity.withMembership

    func testWithMembershipUpdatesIsMember() {
        let community = makeCommunity(id: "1", slug: "cats", isMember: false)
        let updated = community.withMembership(isMember: true, role: .member)
        XCTAssertTrue(updated.isMember)
        XCTAssertEqual(updated.myRole, .member)
    }

    func testWithMembershipClearsRole() {
        let community = makeCommunity(id: "1", slug: "cats", isMember: true)
        let updated = community.withMembership(isMember: false, role: nil)
        XCTAssertFalse(updated.isMember)
        XCTAssertNil(updated.myRole)
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

private func makeCommunity(id: String, slug: String, isMember: Bool) -> RosemountCommunity {
    RosemountCommunity(
        id: id,
        slug: slug,
        name: "Test Community \(id)",
        description: "A test community",
        avatarURL: nil,
        headerURL: nil,
        isPrivate: false,
        memberCount: 10,
        postCount: 5,
        createdAt: "2025-01-01T00:00:00Z",
        instanceHost: "mastodon.social",
        myRole: isMember ? .member : nil,
        isMember: isMember
    )
}
