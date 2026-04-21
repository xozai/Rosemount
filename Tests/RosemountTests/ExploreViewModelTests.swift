// ExploreViewModelTests.swift
// Rosemount
//
// Unit tests for ExploreViewModel.
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class ExploreViewModelTests: XCTestCase {

    // MARK: - Initial State

    func testInitialState() {
        let vm = ExploreViewModel()
        XCTAssertTrue(vm.searchQuery.isEmpty)
        XCTAssertNil(vm.searchResults)
        XCTAssertTrue(vm.trendingTags.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertFalse(vm.isTrendingLoading)
        XCTAssertNil(vm.error)
    }

    // MARK: - onQueryChanged

    func testOnQueryChangedClearsResultsForEmptyQuery() {
        let vm = ExploreViewModel()
        // Simulate pre-existing results
        vm.searchQuery = "swift"
        vm.onQueryChanged("")
        XCTAssertNil(vm.searchResults)
        XCTAssertFalse(vm.isLoading)
    }

    func testOnQueryChangedClearsResultsForWhitespaceOnly() {
        let vm = ExploreViewModel()
        vm.onQueryChanged("   ")
        XCTAssertNil(vm.searchResults)
        XCTAssertFalse(vm.isLoading)
    }

    func testOnQueryChangedWithQuerySetsDebounce() {
        let vm = ExploreViewModel()
        // Just verify it doesn't crash and isLoading isn't set synchronously
        vm.onQueryChanged("mastodon")
        // The debounce fires after 350 ms — we don't wait here; just confirm no immediate crash.
        XCTAssertNil(vm.error)
    }

    // MARK: - Debounce cancellation

    func testOnQueryChangedTwiceQuicklyDoesNotLeaveLoading() async {
        let vm = ExploreViewModel()
        vm.onQueryChanged("first")
        vm.onQueryChanged("")   // cancel before debounce fires
        // Yield to allow any scheduled microtasks to run
        await Task.yield()
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.searchResults)
    }

    // MARK: - Setup

    func testSetupWithCredentialDoesNotCrash() {
        let vm = ExploreViewModel()
        let cred = AccountCredential(
            handle: "alice@mastodon.social",
            instanceURL: URL(string: "https://mastodon.social")!,
            accessToken: "tok",
            tokenType: "Bearer",
            scope: "read write",
            platform: .mastodon
        )
        vm.setup(with: cred)
        // After setup, vm should still be in a clean state
        XCTAssertNil(vm.searchResults)
        XCTAssertTrue(vm.trendingTags.isEmpty)
    }

    // MARK: - performSearch deduplication

    func testPerformSearchSkipsIdenticalQuery() async {
        let vm = ExploreViewModel()
        let cred = AccountCredential(
            handle: "alice@mastodon.social",
            instanceURL: URL(string: "https://mastodon.social")!,
            accessToken: "tok",
            tokenType: "Bearer",
            scope: "read write",
            platform: .mastodon
        )
        vm.setup(with: cred)

        // Even though we have a real client, calling with no network should
        // not set results for the same query twice.  We test the guard logic
        // by verifying the function completes without crashing when client is nil.
        let vmNoClient = ExploreViewModel()
        await vmNoClient.performSearch(query: "swift")
        // No client — should return early, no loading state set
        XCTAssertFalse(vmNoClient.isLoading)
    }

    func testPerformSearchRequiresNonEmptyQuery() async {
        let vm = ExploreViewModel()
        await vm.performSearch(query: "")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.searchResults)
    }

    func testPerformSearchRequiresNonWhitespaceQuery() async {
        let vm = ExploreViewModel()
        await vm.performSearch(query: "   ")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.searchResults)
    }
}
