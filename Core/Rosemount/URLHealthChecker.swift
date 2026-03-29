// Core/Rosemount/URLHealthChecker.swift
// Rosemount
//
// Validates that the required public-facing URLs (Privacy Policy, Terms of
// Service, Support) return HTTP 200 before submission to the App Store.
//
// App Review guidelines require all URLs supplied in App Store Connect to
// be live and return a successful response.  This checker is surfaced in
// the Accessibility Audit screen and can also be invoked from CI.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import OSLog

private let logger = Logger(subsystem: "social.rosemount", category: "URLHealthChecker")

// MARK: - URLCheckResult

struct URLCheckResult: Identifiable {
    let id = UUID()
    let label: String
    let url: URL
    var status: Status

    enum Status: Equatable {
        case pending
        case ok(Int)           // HTTP status code
        case failed(String)    // error message
        case redirect(URL)     // unexpected redirect

        var isHealthy: Bool {
            if case .ok(let code) = self { return code == 200 }
            return false
        }

        var displayString: String {
            switch self {
            case .pending:            return "Checking…"
            case .ok(let code):       return "HTTP \(code) ✓"
            case .failed(let msg):    return "Error: \(msg)"
            case .redirect(let dest): return "Redirects → \(dest.host ?? dest.absoluteString)"
            }
        }
    }
}

// MARK: - URLHealthChecker

@MainActor
final class URLHealthChecker: ObservableObject {

    // MARK: Published state

    @Published private(set) var results: [URLCheckResult] = []
    @Published private(set) var isChecking: Bool = false

    // MARK: URLs to validate

    private static let requiredURLs: [(label: String, url: String)] = [
        ("Privacy Policy",  AppStoreConfig.privacyPolicyURL),
        ("Terms of Service", AppStoreConfig.marketingURL + "/terms"),
        ("Support",          AppStoreConfig.supportURL),
        ("Marketing",        AppStoreConfig.marketingURL),
    ]

    // MARK: Init

    init() {
        results = Self.requiredURLs.compactMap { entry in
            guard let url = URL(string: entry.url) else { return nil }
            return URLCheckResult(label: entry.label, url: url, status: .pending)
        }
    }

    // MARK: Check

    /// Fires HEAD requests to all required URLs and updates `results`.
    func checkAll() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        // Reset to pending
        for i in results.indices { results[i].status = .pending }

        await withTaskGroup(of: (Int, URLCheckResult.Status).self) { group in
            for (index, result) in results.enumerated() {
                group.addTask { [url = result.url] in
                    let status = await Self.check(url: url)
                    return (index, status)
                }
            }
            for await (index, status) in group {
                results[index].status = status
                let label = results[index].label
                switch status {
                case .ok(let code):
                    logger.info("URL check passed: \(label) → HTTP \(code)")
                case .failed(let msg):
                    logger.error("URL check failed: \(label) → \(msg)")
                case .redirect(let dest):
                    logger.warning("URL check redirect: \(label) → \(dest.absoluteString)")
                case .pending:
                    break
                }
            }
        }
    }

    // MARK: Private helpers

    private static func check(url: URL) async -> URLCheckResult.Status {
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.httpShouldFollowRedirects = false
        let session = URLSession(configuration: sessionConfig)

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .failed("Non-HTTP response")
            }
            if (300..<400).contains(http.statusCode),
               let location = http.value(forHTTPHeaderField: "Location"),
               let dest = URL(string: location) {
                return .redirect(dest)
            }
            return .ok(http.statusCode)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    // MARK: Convenience

    var allHealthy: Bool {
        results.allSatisfy { $0.status.isHealthy }
    }

    var summary: String {
        let passing = results.filter { $0.status.isHealthy }.count
        return "\(passing)/\(results.count) URLs healthy"
    }
}
