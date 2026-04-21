// ProfileViewModelTests.swift
// Rosemount
//
// Unit tests for ProfileViewModel — initial state, computed properties,
// guard logic, and social-action follow button title variants.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class ProfileViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = ProfileViewModel()
        XCTAssertNil(vm.account)
        XCTAssertTrue(vm.statuses.isEmpty)
        XCTAssertNil(vm.relationship)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isLoadingMore)
        XCTAssertNil(vm.error)
        XCTAssertTrue(vm.hasMore)
    }

    // MARK: - isOwnProfile

    func testIsOwnProfileFalseWhenAccountNil() {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        XCTAssertFalse(vm.isOwnProfile)
    }

    func testIsOwnProfileFalseWhenIdsDiffer() {
        let credId = UUID()
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: credId, handle: "alice"))
        vm.account = makeAccount(id: UUID().uuidString)   // different id
        XCTAssertFalse(vm.isOwnProfile)
    }

    func testIsOwnProfileTrueWhenIdsMatch() {
        let credId = UUID()
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: credId, handle: "alice"))
        vm.account = makeAccount(id: credId.uuidString)
        XCTAssertTrue(vm.isOwnProfile)
    }

    // MARK: - followButtonTitle

    func testFollowButtonTitleWhenNoRelationship() {
        let vm = ProfileViewModel()
        vm.account = makeAccount(id: "1")
        XCTAssertEqual(vm.followButtonTitle, "Follow")
    }

    func testFollowButtonTitleWhenFollowing() {
        let vm = ProfileViewModel()
        vm.relationship = makeRelationship(id: "1", following: true, requested: false)
        XCTAssertEqual(vm.followButtonTitle, "Unfollow")
    }

    func testFollowButtonTitleWhenRequested() {
        let vm = ProfileViewModel()
        vm.relationship = makeRelationship(id: "1", following: false, requested: true)
        XCTAssertEqual(vm.followButtonTitle, "Requested")
    }

    func testFollowButtonTitleWhenNotFollowing() {
        let vm = ProfileViewModel()
        vm.relationship = makeRelationship(id: "1", following: false, requested: false)
        XCTAssertEqual(vm.followButtonTitle, "Follow")
    }

    // MARK: - load guard

    func testLoadNoopsWithoutClient() async {
        let vm = ProfileViewModel()
        await vm.load(accountId: "123")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.account)
    }

    // MARK: - loadMore guards

    func testLoadMoreNoopsWithoutClient() async {
        let vm = ProfileViewModel()
        await vm.loadMore()
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testLoadMoreNoopsWhenHasMoreFalse() async {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        vm.hasMore = false
        await vm.loadMore()
        XCTAssertFalse(vm.isLoadingMore)
    }

    func testLoadMoreNoopsWhenAlreadyLoadingMore() async {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        vm.isLoadingMore = true
        await vm.loadMore()
        XCTAssertTrue(vm.isLoadingMore)
    }

    // MARK: - Social action guards

    func testToggleFollowNoopsWithoutAccount() async {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        await vm.toggleFollow()   // account is nil → no-op
        XCTAssertNil(vm.relationship)
    }

    func testBlockNoopsWithoutAccount() async {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        await vm.block()
        XCTAssertNil(vm.relationship)
    }

    func testMuteNoopsWithoutAccount() async {
        let vm = ProfileViewModel()
        vm.setup(with: makeCred(id: UUID(), handle: "alice"))
        await vm.mute()
        XCTAssertNil(vm.relationship)
    }
}

// MARK: - Helpers

private func makeCred(id: UUID, handle: String) -> AccountCredential {
    AccountCredential(
        id: id,
        handle: handle,
        instanceURL: URL(string: "https://mastodon.social")!,
        accessToken: "tok",
        tokenType: "Bearer",
        scope: "read write",
        platform: .mastodon
    )
}

private func makeAccount(id: String) -> MastodonAccount {
    MastodonAccount(
        id: id,
        username: "user",
        acct: "user@mastodon.social",
        displayName: "User",
        locked: false,
        bot: false,
        createdAt: "2024-01-01T00:00:00Z",
        note: "",
        url: "https://mastodon.social/@user",
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

private func makeRelationship(id: String, following: Bool, requested: Bool) -> MastodonRelationship {
    MastodonRelationship(
        id: id,
        following: following,
        showingReblogs: true,
        notifying: false,
        followedBy: false,
        blocking: false,
        blockedBy: false,
        muting: false,
        mutingNotifications: false,
        requested: requested,
        domainBlocking: false,
        endorsed: false
    )
}
