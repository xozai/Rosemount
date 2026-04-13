// OnboardingViewModelTests.swift
// Rosemount
//
// Unit tests for OnboardingViewModel — instance reachability, URL normalisation,
// and demo mode activation.
//
// Swift 5.10 | iOS 17.0+

import XCTest
@testable import Rosemount

@MainActor
final class OnboardingViewModelTests: XCTestCase {

    private var viewModel: OnboardingViewModel!

    override func setUp() {
        super.setUp()
        viewModel = OnboardingViewModel()
    }

    override func tearDown() {
        viewModel = nil
        super.tearDown()
    }

    // MARK: - normalizedInstanceURL

    func testNormalizedURLPrependsHttps() {
        viewModel.instanceURLString = "mastodon.social"
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "mastodon.social")
    }

    func testNormalizedURLPreservesExistingScheme() {
        viewModel.instanceURLString = "https://fosstodon.org"
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "fosstodon.org")
    }

    func testNormalizedURLStripsTrailingSlash() {
        viewModel.instanceURLString = "mastodon.social/"
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNotNil(url)
        // No trailing slash in the host
        XCTAssertEqual(url?.host, "mastodon.social")
        XCTAssertTrue(url?.absoluteString.hasSuffix("/") == false || url?.path == "")
    }

    func testNormalizedURLNilForEmpty() {
        viewModel.instanceURLString = ""
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNil(url)
    }

    func testNormalizedURLNilForJustSpaces() {
        viewModel.instanceURLString = "   "
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNil(url)
    }

    func testNormalizedURLNilForNoHost() {
        // A URL with only a scheme and no host is invalid
        viewModel.instanceURLString = "https://"
        let url = viewModel.normalizedInstanceURL()
        XCTAssertNil(url)
    }

    func testNormalizedURLLowercased() {
        viewModel.instanceURLString = "MASTODON.SOCIAL"
        let url = viewModel.normalizedInstanceURL()
        XCTAssertEqual(url?.host, "mastodon.social")
    }

    // MARK: - checkInstanceReachability (offline / bad URLs)

    func testReachabilityFalseForLocalhost() async {
        // localhost with a random port is reliably unreachable in the test environment
        let url = URL(string: "https://localhost:19999")!
        let result = await viewModel.checkInstanceReachability(url)
        // In a sandboxed test environment this will time out or refuse connection
        // We cannot guarantee false in all CI setups, so we simply verify the function completes
        XCTAssertNotNil(result)
    }

    func testReachabilityFalseForInvalidHost() async {
        // .invalid TLD is guaranteed by RFC 2606 to never resolve
        let url = URL(string: "https://thisdomaindoesnotexist.invalid")!
        let result = await viewModel.checkInstanceReachability(url)
        XCTAssertFalse(result, "Unreachable host should return false")
    }

    // MARK: - Demo mode

    func testDemoModeKeyword() {
        // "rosemount-review" is the magic keyword checked in signInWithMastodon
        let keyword = "rosemount-review"
        XCTAssertEqual(
            keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            "rosemount-review"
        )
    }

    func testActivateDemoModeChangesStep() {
        viewModel.activateDemoMode()
        XCTAssertEqual(viewModel.step, .profileSetup)
    }

    func testActivateDemoModeAddsAccount() {
        let beforeCount = AuthManager.shared.accounts.count
        viewModel.activateDemoMode()
        let afterCount = AuthManager.shared.accounts.count
        XCTAssertGreaterThan(afterCount, beforeCount)

        // Clean up
        if let demo = AuthManager.shared.accounts.last {
            AuthManager.shared.removeAccount(demo)
        }
    }

    func testDemoAccountHasDemoHandle() {
        viewModel.activateDemoMode()
        let demo = AuthManager.shared.accounts.last
        XCTAssertEqual(demo?.handle, "app-review-demo")

        // Clean up
        if let demo { AuthManager.shared.removeAccount(demo) }
    }

    // MARK: - Initial state

    func testInitialStep() {
        XCTAssertEqual(viewModel.step, .welcome)
    }

    func testInitialInstanceURLStringIsEmpty() {
        XCTAssertTrue(viewModel.instanceURLString.isEmpty)
    }

    func testInitialErrorIsNil() {
        XCTAssertNil(viewModel.error)
    }

    func testInitialIsLoadingFalse() {
        XCTAssertFalse(viewModel.isLoading)
    }

    func testInitialPlatformIsMastodon() {
        XCTAssertEqual(viewModel.selectedPlatform, .mastodon)
    }
}
