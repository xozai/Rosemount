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
// PixelfedOAuthService  — defined in Core/Pixelfed/PixelfedOAuth.swift (TODO: define)

// MARK: - OnboardingStep

/// Drives the multi-step onboarding navigation.
enum OnboardingStep: Equatable {
    case welcome
    case instanceEntry
    case authenticating
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
    // PixelfedOAuthService — TODO: define in Core/Pixelfed/PixelfedOAuth.swift
    private let pixelfedOAuth = PixelfedOAuthService()

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
        guard let instanceURL = normalizedInstanceURL() else {
            error = "The instance URL "\(instanceURLString)" is not valid. Check for typos and try again."
            return
        }

        isLoading = true
        step = .authenticating
        error = nil

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
        guard let instanceURL = normalizedInstanceURL() else {
            error = "The instance URL "\(instanceURLString)" is not valid. Check for typos and try again."
            return
        }

        isLoading = true
        step = .authenticating
        error = nil

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

    // MARK: - Rosemount Sign-In (Phase 1 Stub)

    /// Stub for native Rosemount account creation.
    /// Shows a "coming soon" message in Phase 1.
    func signInWithRosemount() async {
        // TODO: Phase 1 — implement native Rosemount account registration.
        error = "Native Rosemount accounts are coming soon. In the meantime, sign in with your Mastodon or Pixelfed account."
    }
}
