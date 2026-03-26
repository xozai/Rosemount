// OnboardingViewModel.swift
// Rosemount
//
// ViewModel for the onboarding / sign-in flow.
// Handles instance URL normalisation, platform selection,
// and OAuth sign-in for Mastodon and Pixelfed.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import AuthenticationServices
import Observation

// AuthManager           — defined in Core/Auth/AuthManager.swift
// AccountCredential     — defined in Core/Auth/AuthManager.swift
// FederationPlatform    — defined in Core/Auth/AuthManager.swift
// MastodonOAuthService  — defined in Core/Mastodon/MastodonOAuth.swift
// PixelfedOAuthService  — defined in Core/Pixelfed/PixelfedOAuth.swift

// MARK: - OnboardingStep

/// Drives the multi-step onboarding navigation.
enum OnboardingStep: Equatable {
    case welcome
    case instanceEntry
    case authenticating
    case registration        // Native Rosemount account creation form
    case profileSetup
}

// MARK: - OnboardingViewModel

@Observable
@MainActor
final class OnboardingViewModel {

    // MARK: - State

    var step: OnboardingStep = .welcome
    var instanceURLString: String = ""
    var selectedPlatform: FederationPlatform = .mastodon
    var isLoading: Bool = false
    /// Non-`nil` when an error has occurred; used to drive an error alert.
    var error: String? = nil

    // MARK: - Private

    private let mastodonOAuth = MastodonOAuthService()
    private let pixelfedOAuth = PixelfedOAuthService()
    private let rosemountAPI  = RosemountAPIClient()

    // MARK: - App Review Demo Mode

    /// Activates the hidden App Review demo mode.
    ///
    /// Triggered when the user types "rosemount-review" in the instance URL field.
    /// Creates a local-only demo credential so reviewers can navigate all tabs
    /// without a live server. The empty access token causes all API calls to fail
    /// gracefully with 401, which the app handles via AuthManager.removeAccount.
    func activateDemoMode() {
        let demoCredential = AccountCredential(
            handle: "app-review-demo",
            instanceURL: URL(string: "https://mastodon.social")!,
            accessToken: "",
            tokenType: "Bearer",
            scope: "read write follow",
            platform: .mastodon,
            actorURL: nil,
            displayName: "App Review Demo",
            avatarURL: nil
        )
        AuthManager.shared.addAccount(demoCredential)
        step = .profileSetup
    }

    // MARK: - Instance Reachability

    /// Performs a HEAD request to `/api/v1/instance` with a 5-second timeout.
    ///
    /// Returns `true` when the server responds with any HTTP status (even 4xx),
    /// indicating the server is reachable. Returns `false` on network error or timeout.
    ///
    /// Always returns `true` for "rosemount-review" (demo mode bypass).
    func checkInstanceReachability(_ instanceURL: URL) async -> Bool {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/instance"
        guard let url = components.url else { return false }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 5
        config.timeoutIntervalForResource = 5
        let session = URLSession(configuration: config)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"

        do {
            let (_, response) = try await session.data(for: request)
            return response is HTTPURLResponse
        } catch {
            return false
        }
    }

    // MARK: - URL Normalisation

    /// Returns a normalised `URL` from `instanceURLString`.
    ///
    /// Prepends `https://` when the user omits a scheme.
    /// Returns `nil` when the resulting string is not a valid URL.
    func normalizedInstanceURL() -> URL? {
        var raw = instanceURLString
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        // Strip any trailing slashes.
        while raw.hasSuffix("/") { raw = String(raw.dropLast()) }

        // Prepend scheme when missing.
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") {
            raw = "https://\(raw)"
        }

        guard let url = URL(string: raw),
              url.host != nil else {
            return nil
        }
        return url
    }

    // MARK: - Mastodon Sign-In

    /// Runs the full Mastodon OAuth 2.0 flow:
    /// 1. Normalises the instance URL.
    /// 2. Registers the Rosemount app on the instance.
    /// 3. Presents ASWebAuthenticationSession for user authorisation.
    /// 4. Exchanges the code for a token and verifies credentials.
    /// 5. Saves the account via `AuthManager.shared.addAccount(_:)`.
    ///
    /// - Parameter presentationAnchor: The window used to anchor the web auth UI.
    func signInWithMastodon(presentationAnchor: ASPresentationAnchor) async {
        if instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines) == "rosemount-review" {
            activateDemoMode()
            return
        }
        guard let instanceURL = normalizedInstanceURL() else {
            error = "The instance URL "\(instanceURLString)" is not valid. Check for typos and try again."
            return
        }

        isLoading = true
        error = nil

        let reachable = await checkInstanceReachability(instanceURL)
        guard reachable else {
            error = "Could not reach \(instanceURL.host ?? instanceURL.absoluteString). Check the address and your internet connection, then try again."
            isLoading = false
            return
        }

        step = .authenticating

        do {
            // 1. Register the app on the instance.
            let app = try await mastodonOAuth.registerApp(instanceURL: instanceURL)

            // 2. Run the authorization code flow.
            let token = try await mastodonOAuth.authorize(
                app: app,
                instanceURL: instanceURL,
                presentationAnchor: presentationAnchor
            )

            // 3. Verify credentials to get account info.
            let account = try await mastodonOAuth.verifyCredentials(
                instanceURL: instanceURL,
                token: token
            )

            // 4. Build and store the credential.
            let credential = AccountCredential(
                handle: account.acct,
                instanceURL: instanceURL,
                accessToken: token.accessToken,
                tokenType: token.tokenType,
                scope: token.scope,
                platform: .mastodon,
                actorURL: URL(string: account.url),
                displayName: account.displayName.isEmpty ? nil : account.displayName,
                avatarURL: URL(string: account.avatar)
            )

            AuthManager.shared.addAccount(credential)
            step = .profileSetup

        } catch MastodonOAuthError.authorizationCancelled {
            // User cancelled — return to instance entry without showing an error.
            step = .instanceEntry
        } catch {
            self.error = error.localizedDescription
            step = .instanceEntry
        }

        isLoading = false
    }

    // MARK: - Pixelfed Sign-In

    /// Runs the Pixelfed OAuth 2.0 flow (mirrors the Mastodon flow with a different service).
    ///
    /// - Parameter presentationAnchor: The window used to anchor the web auth UI.
    func signInWithPixelfed(presentationAnchor: ASPresentationAnchor) async {
        if instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines) == "rosemount-review" {
            activateDemoMode()
            return
        }
        guard let instanceURL = normalizedInstanceURL() else {
            error = "The instance URL "\(instanceURLString)" is not valid. Check for typos and try again."
            return
        }

        isLoading = true
        error = nil

        let reachable = await checkInstanceReachability(instanceURL)
        guard reachable else {
            error = "Could not reach \(instanceURL.host ?? instanceURL.absoluteString). Check the address and your internet connection, then try again."
            isLoading = false
            return
        }

        step = .authenticating

        do {
            // PixelfedOAuthService.registerApp and authorize mirror MastodonOAuthService.
            let app = try await pixelfedOAuth.registerApp(instanceURL: instanceURL)

            let token = try await pixelfedOAuth.authorize(
                app: app,
                instanceURL: instanceURL,
                presentationAnchor: presentationAnchor
            )

            let account = try await pixelfedOAuth.verifyCredentials(
                instanceURL: instanceURL,
                token: token
            )

            let credential = AccountCredential(
                handle: account.acct,
                instanceURL: instanceURL,
                accessToken: token.accessToken,
                tokenType: token.tokenType,
                scope: token.scope,
                platform: .pixelfed,
                actorURL: URL(string: account.url),
                displayName: account.displayName.isEmpty ? nil : account.displayName,
                avatarURL: URL(string: account.avatar)
            )

            AuthManager.shared.addAccount(credential)
            step = .profileSetup

        } catch MastodonOAuthError.authorizationCancelled {
            step = .instanceEntry
        } catch {
            self.error = error.localizedDescription
            step = .instanceEntry
        }

        isLoading = false
    }

    // MARK: - Rosemount Registration

    /// Navigates to the native Rosemount account registration form.
    func signInWithRosemount() async {
        step = .registration
    }

    /// Submits a new account registration to the Rosemount back-end.
    ///
    /// On success, the account is added to `AuthManager` and the app transitions
    /// to the authenticated state.
    func submitRegistration(username: String, email: String, password: String) async {
        guard !username.isEmpty, !email.isEmpty, !password.isEmpty else {
            error = "Please fill in all fields."
            return
        }

        isLoading = true
        step = .authenticating
        error = nil

        do {
            let response = try await rosemountAPI.register(
                username: username,
                email: email,
                password: password
            )

            guard let instanceURL = URL(string: response.instanceURL) else {
                error = "The server returned an invalid instance URL."
                step = .registration
                isLoading = false
                return
            }

            let credential = AccountCredential(
                handle: response.handle,
                instanceURL: instanceURL,
                accessToken: response.accessToken,
                tokenType: response.tokenType,
                scope: response.scope,
                platform: .rosemount,
                actorURL: response.actorURL.flatMap(URL.init(string:)),
                displayName: response.displayName,
                avatarURL: response.avatarURL.flatMap(URL.init(string:))
            )

            AuthManager.shared.addAccount(credential)
            step = .profileSetup

        } catch {
            self.error = error.localizedDescription
            step = .registration
        }

        isLoading = false
    }
}
