// Rosemount — MastodonOAuth.swift
// Mastodon OAuth 2.0 flow using ASWebAuthenticationSession.
// Swift 5.10 | iOS 17.0+

import Foundation
import AuthenticationServices

// MARK: - MastodonApp

/// The application registration returned by POST /api/v1/apps.
struct MastodonApp: Codable {
    let id: String
    let name: String
    let website: String?
    let redirectUri: String
    let clientId: String
    let clientSecret: String
    let vapidKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case website
        case redirectUri      = "redirect_uri"
        case clientId         = "client_id"
        case clientSecret     = "client_secret"
        case vapidKey         = "vapid_key"
    }
}

// MARK: - MastodonToken

/// The access token returned by POST /oauth/token.
struct MastodonToken: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken  = "access_token"
        case tokenType    = "token_type"
        case scope
        case createdAt    = "created_at"
    }
}

// MARK: - MastodonOAuthError

enum MastodonOAuthError: Error, LocalizedError {
    case appRegistrationFailed(String)
    case authorizationCancelled
    case tokenExchangeFailed(String)
    case invalidCallbackURL

    var errorDescription: String? {
        switch self {
        case .appRegistrationFailed(let message):
            return "Mastodon app registration failed: \(message)"
        case .authorizationCancelled:
            return "The Mastodon authorization flow was cancelled."
        case .tokenExchangeFailed(let message):
            return "Mastodon token exchange failed: \(message)"
        case .invalidCallbackURL:
            return "The OAuth callback URL from Mastodon was invalid or missing the authorization code."
        }
    }
}

// MARK: - MastodonOAuthService

/// Actor-isolated Mastodon OAuth 2.0 service.
///
/// Typical usage:
/// 1. `registerApp(instanceURL:)` — register the app on the instance.
/// 2. `authorize(app:instanceURL:presentationAnchor:)` — present the web auth flow and exchange the code.
/// 3. `verifyCredentials(instanceURL:token:)` — fetch the authenticated account details.
actor MastodonOAuthService {

    // MARK: - Constants

    private static let redirectURI  = "rosemount://oauth/mastodon"
    private static let scopes       = "read write follow push"
    private static let clientName   = "Rosemount"
    private static let website      = "https://rosemount.app"

    // MARK: - JSON Decoder

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - App Registration

    /// Registers the Rosemount application on the given Mastodon instance.
    ///
    /// Sends `POST /api/v1/apps` and returns the client credentials.
    func registerApp(instanceURL: URL) async throws -> MastodonApp {
        var components = URLComponents(url: instanceURL.appendingPathComponent("api/v1/apps"), resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/apps"

        var request = URLRequest(url: instanceURL.appendingPathComponent("api/v1/apps"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_name":   Self.clientName,
            "redirect_uris": Self.redirectURI,
            "scopes":        Self.scopes,
            "website":       Self.website
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MastodonOAuthError.appRegistrationFailed(message)
        }

        do {
            return try decoder.decode(MastodonApp.self, from: data)
        } catch {
            throw MastodonOAuthError.appRegistrationFailed("Failed to decode app registration response: \(error.localizedDescription)")
        }
    }

    // MARK: - Authorization

    /// Runs the full OAuth 2.0 authorization code flow:
    /// 1. Presents the Mastodon instance login page in an `ASWebAuthenticationSession`.
    /// 2. Captures the authorization code from the redirect URI.
    /// 3. Exchanges the code for an access token.
    ///
    /// - Parameters:
    ///   - app: The registered Mastodon app credentials.
    ///   - instanceURL: Base URL of the Mastodon instance.
    ///   - presentationAnchor: The window used to anchor the authentication session UI.
    /// - Returns: A `MastodonToken` containing the access token.
    func authorize(
        app: MastodonApp,
        instanceURL: URL,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> MastodonToken {
        // 1. Build the authorization URL.
        var components = URLComponents(url: instanceURL.appendingPathComponent("oauth/authorize"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id",     value: app.clientId),
            URLQueryItem(name: "redirect_uri",  value: Self.redirectURI),
            URLQueryItem(name: "scope",         value: Self.scopes)
        ]
        guard let authURL = components.url else {
            throw MastodonOAuthError.appRegistrationFailed("Could not build authorization URL")
        }

        // 2. Present the ASWebAuthenticationSession and capture the callback URL.
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "rosemount"
            ) { callbackURL, error in
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: MastodonOAuthError.authorizationCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: MastodonOAuthError.invalidCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = PresentationAnchorProvider(anchor: presentationAnchor)
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // 3. Extract the authorization code from the callback URL.
        guard
            let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = components.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw MastodonOAuthError.invalidCallbackURL
        }

        // 4. Exchange the code for an access token.
        return try await exchangeCodeForToken(
            code: code,
            app: app,
            instanceURL: instanceURL
        )
    }

    // MARK: - Verify Credentials

    /// Verifies the token is valid by fetching the authenticated account.
    ///
    /// Calls `GET /api/v1/accounts/verify_credentials`.
    func verifyCredentials(instanceURL: URL, token: MastodonToken) async throws -> MastodonAccount {
        // MastodonAccount is defined in MastodonAccount.swift
        var request = URLRequest(url: instanceURL.appendingPathComponent("api/v1/accounts/verify_credentials"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MastodonOAuthError.tokenExchangeFailed("Credential verification failed: \(message)")
        }

        let accountDecoder = JSONDecoder()
        accountDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return try accountDecoder.decode(MastodonAccount.self, from: data)
    }

    // MARK: - Private Helpers

    private func exchangeCodeForToken(
        code: String,
        app: MastodonApp,
        instanceURL: URL
    ) async throws -> MastodonToken {
        var request = URLRequest(url: instanceURL.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "client_id":     app.clientId,
            "client_secret": app.clientSecret,
            "redirect_uri":  Self.redirectURI,
            "scope":         Self.scopes
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw MastodonOAuthError.tokenExchangeFailed(message)
        }

        do {
            return try decoder.decode(MastodonToken.self, from: data)
        } catch {
            throw MastodonOAuthError.tokenExchangeFailed("Failed to decode token response: \(error.localizedDescription)")
        }
    }
}

// MARK: - PresentationAnchorProvider

/// Minimal `ASWebAuthenticationPresentationContextProviding` implementation
/// that wraps a pre-captured `ASPresentationAnchor`.
private final class PresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
