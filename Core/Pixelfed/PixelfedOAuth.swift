// PixelfedOAuth.swift
// Rosemount
//
// Pixelfed OAuth 2.0 flow using ASWebAuthenticationSession.
// Pixelfed implements the Mastodon-compatible OAuth 2.0 API (Laravel Passport under the hood),
// so the flow mirrors MastodonOAuth with Pixelfed-specific constants and endpoints.
// Swift 5.10 | iOS 17.0+
//
// MastodonAccount — Defined in MastodonAccount.swift (Pixelfed uses the same account schema)

import Foundation
import AuthenticationServices

// MARK: - PixelfedApp

/// The application registration returned by POST /api/v1/apps on a Pixelfed instance.
struct PixelfedApp: Codable {
    let id: String
    let name: String
    let website: String?
    let redirectUri: String
    let clientId: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case website
        case redirectUri  = "redirect_uri"
        case clientId     = "client_id"
        case clientSecret = "client_secret"
    }
}

// MARK: - PixelfedToken

/// The access token returned by POST /oauth/token on a Pixelfed instance.
struct PixelfedToken: Codable {
    let accessToken: String
    let tokenType: String
    let scope: String
    /// Unix timestamp of token creation.
    let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType   = "token_type"
        case scope
        case createdAt   = "created_at"
    }
}

// MARK: - PixelfedOAuthError

enum PixelfedOAuthError: Error, LocalizedError {
    case appRegistrationFailed(String)
    case authorizationCancelled
    case tokenExchangeFailed(String)
    case invalidCallbackURL

    var errorDescription: String? {
        switch self {
        case .appRegistrationFailed(let message):
            return "Pixelfed app registration failed: \(message)"
        case .authorizationCancelled:
            return "The Pixelfed authorization flow was cancelled."
        case .tokenExchangeFailed(let message):
            return "Pixelfed token exchange failed: \(message)"
        case .invalidCallbackURL:
            return "The OAuth callback URL from Pixelfed was invalid or missing the authorization code."
        }
    }
}

// MARK: - PixelfedOAuthService

/// Actor-isolated Pixelfed OAuth 2.0 service.
///
/// Pixelfed exposes the same OAuth endpoints as Mastodon (via Laravel Passport),
/// so the implementation closely mirrors `MastodonOAuthService`.
///
/// Typical usage:
/// 1. `registerApp(instanceURL:)` — register the client on the Pixelfed instance.
/// 2. `authorize(app:instanceURL:presentationAnchor:)` — present the web auth flow and exchange the code.
/// 3. `verifyCredentials(instanceURL:token:)` — fetch the authenticated account.
actor PixelfedOAuthService {

    // MARK: - Constants

    private static let redirectURI  = "rosemount://oauth/pixelfed"
    private static let scopes       = "read write follow"
    private static let clientName   = "Rosemount"
    private static let website      = "https://rosemount.app"

    // MARK: - JSON Decoder

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - App Registration

    /// Registers the Rosemount application on the given Pixelfed instance.
    ///
    /// Sends `POST /api/v1/apps` (Mastodon-compatible endpoint) and returns the client credentials.
    func registerApp(instanceURL: URL) async throws -> PixelfedApp {
        var request = URLRequest(url: instanceURL.appendingPathComponent("api/v1/apps"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_name":   Self.clientName,
            "redirect_uris": Self.redirectURI,
            "scopes":        Self.scopes,
            "website":       Self.website,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PixelfedOAuthError.appRegistrationFailed(message)
        }

        do {
            return try decoder.decode(PixelfedApp.self, from: data)
        } catch {
            throw PixelfedOAuthError.appRegistrationFailed(
                "Failed to decode app registration response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Authorization

    /// Runs the full OAuth 2.0 authorization code flow for Pixelfed:
    /// 1. Presents the Pixelfed instance login page at `/oauth/authorize` in an `ASWebAuthenticationSession`.
    /// 2. Captures the authorization code from the `rosemount://oauth/pixelfed` redirect.
    /// 3. Exchanges the code for an access token via `/oauth/token`.
    ///
    /// - Parameters:
    ///   - app: The registered Pixelfed app credentials.
    ///   - instanceURL: Base URL of the Pixelfed instance.
    ///   - presentationAnchor: The window used to anchor the authentication session UI.
    /// - Returns: A `PixelfedToken` containing the access token.
    func authorize(
        app: PixelfedApp,
        instanceURL: URL,
        presentationAnchor: ASPresentationAnchor
    ) async throws -> PixelfedToken {
        // 1. Build the /oauth/authorize URL.
        var components = URLComponents(
            url: instanceURL.appendingPathComponent("oauth/authorize"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id",     value: app.clientId),
            URLQueryItem(name: "redirect_uri",  value: Self.redirectURI),
            URLQueryItem(name: "scope",         value: Self.scopes),
        ]
        guard let authURL = components.url else {
            throw PixelfedOAuthError.appRegistrationFailed("Could not build authorization URL")
        }

        // 2. Present ASWebAuthenticationSession and capture the callback URL.
        let callbackURL = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: "rosemount"
            ) { callbackURL, error in
                if let error = error {
                    if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                        continuation.resume(throwing: PixelfedOAuthError.authorizationCancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: PixelfedOAuthError.invalidCallbackURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = PixelfedPresentationAnchorProvider(anchor: presentationAnchor)
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        // 3. Extract the authorization code from the callback URL.
        guard
            let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code = callbackComponents.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            throw PixelfedOAuthError.invalidCallbackURL
        }

        // 4. Exchange the code for a token.
        return try await exchangeCodeForToken(code: code, app: app, instanceURL: instanceURL)
    }

    // MARK: - Verify Credentials

    /// Verifies the token is valid by fetching the authenticated Pixelfed account.
    ///
    /// Pixelfed exposes the Mastodon-compatible `GET /api/v1/accounts/verify_credentials` endpoint.
    ///
    /// - Returns: A `MastodonAccount` (Pixelfed uses the same account schema as Mastodon).
    func verifyCredentials(instanceURL: URL, token: PixelfedToken) async throws -> MastodonAccount {
        // MastodonAccount is defined in MastodonAccount.swift
        var request = URLRequest(
            url: instanceURL.appendingPathComponent("api/v1/accounts/verify_credentials")
        )
        request.httpMethod = "GET"
        request.setValue("Bearer \(token.accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PixelfedOAuthError.tokenExchangeFailed("Credential verification failed: \(message)")
        }

        let accountDecoder = JSONDecoder()
        accountDecoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try accountDecoder.decode(MastodonAccount.self, from: data)
        } catch {
            throw PixelfedOAuthError.tokenExchangeFailed(
                "Failed to decode account response: \(error.localizedDescription)"
            )
        }
    }

    // MARK: - Private Helpers

    private func exchangeCodeForToken(
        code: String,
        app: PixelfedApp,
        instanceURL: URL
    ) async throws -> PixelfedToken {
        var request = URLRequest(url: instanceURL.appendingPathComponent("oauth/token"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "grant_type":    "authorization_code",
            "code":          code,
            "client_id":     app.clientId,
            "client_secret": app.clientSecret,
            "redirect_uri":  Self.redirectURI,
            "scope":         Self.scopes,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw PixelfedOAuthError.tokenExchangeFailed(message)
        }

        do {
            return try decoder.decode(PixelfedToken.self, from: data)
        } catch {
            throw PixelfedOAuthError.tokenExchangeFailed(
                "Failed to decode token response: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - PixelfedPresentationAnchorProvider

/// Minimal `ASWebAuthenticationPresentationContextProviding` implementation
/// that wraps a pre-captured `ASPresentationAnchor` for Pixelfed auth sessions.
private final class PixelfedPresentationAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let anchor: ASPresentationAnchor

    init(anchor: ASPresentationAnchor) {
        self.anchor = anchor
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        anchor
    }
}
