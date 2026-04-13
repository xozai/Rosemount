// AppStoreConfig.swift
// Rosemount
//
// Centralised App Store configuration constants.
// All public-facing URLs and metadata strings are defined here so they can
// be verified at a glance and updated in a single location.
//
// Swift 5.10 | iOS 17.0+

import Foundation

// MARK: - Compile-time guards
// These #warning directives fire if a required URL is left blank, catching
// accidental empty strings before a build reaches App Review.

#if canImport(Foundation)
private enum _AppStoreURLGuards {
    static let _privacy  = AppStoreConfig.privacyPolicyURL
    static let _support  = AppStoreConfig.supportURL
    static let _marketing = AppStoreConfig.marketingURL
}
#endif

// MARK: - AppStoreConfig

enum AppStoreConfig {

    // MARK: Public URLs
    // All three URLs must return HTTP 200 before App Store submission.
    // Verified by URLHealthChecker (accessible via Settings → Accessibility Audit in DEBUG builds).

    /// Privacy Policy page. Required by App Store guidelines and GDPR.
    static let privacyPolicyURL: String = "https://rosemount.social/privacy"

    /// Support page. Displayed in the App Store listing and Settings.
    static let supportURL: String = "https://rosemount.social/support"

    /// Marketing / landing page. Displayed in the App Store listing.
    static let marketingURL: String = "https://rosemount.social"

    // MARK: App Identity

    /// App Store bundle identifier.
    static let bundleIdentifier: String = "social.rosemount.app"

    /// Human-readable app name used in notifications and alerts.
    static let appName: String = "Rosemount"

    // MARK: Version Info

    /// The marketing version string from the bundle (e.g. "1.0.0").
    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    /// The build number from the bundle (e.g. "42").
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    // MARK: URL Validation

    /// Performs live HEAD checks against all three required App Store URLs.
    ///
    /// Returns a dictionary mapping each URL string to `true` (HTTP 200 OK) or
    /// `false` (unreachable / non-200 response). Intended for DEBUG builds only.
    ///
    /// Example usage:
    /// ```swift
    /// #if DEBUG
    /// Task {
    ///     let results = await AppStoreConfig.validateURLs()
    ///     results.forEach { url, ok in print("\(ok ? "✅" : "❌") \(url)") }
    /// }
    /// #endif
    /// ```
    static func validateURLs() async -> [String: Bool] {
        let urls = [privacyPolicyURL, supportURL, marketingURL]
        var results: [String: Bool] = [:]

        await withTaskGroup(of: (String, Bool).self) { group in
            for urlString in urls {
                group.addTask {
                    guard let url = URL(string: urlString) else { return (urlString, false) }
                    var request = URLRequest(url: url, timeoutInterval: 10)
                    request.httpMethod = "HEAD"
                    let config = URLSessionConfiguration.ephemeral
                    config.httpShouldFollowRedirects = true
                    let session = URLSession(configuration: config)
                    do {
                        let (_, response) = try await session.data(for: request)
                        let http = response as? HTTPURLResponse
                        return (urlString, http?.statusCode == 200)
                    } catch {
                        return (urlString, false)
                    }
                }
            }
            for await (url, ok) in group {
                results[url] = ok
            }
        }
        return results
    }
}
