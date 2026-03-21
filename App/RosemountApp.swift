// RosemountApp.swift
// Rosemount
//
// @main SwiftUI App entry point.
// Sets up SwiftData ModelContainer, injects AuthManager into the environment,
// routes between ContentView and OnboardingView, and handles OAuth deep-link callbacks.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import SwiftData
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Request authorisation for remote (push) notifications.
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        // TODO: Forward the device token to the Rosemount push-notification server.
        let tokenString = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[AppDelegate] Registered for remote notifications. Token: \(tokenString)")
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[AppDelegate] Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

// MARK: - RosemountApp

@main
struct RosemountApp: App {

    // MARK: UIApplicationDelegate bridge

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: Auth state

    @State private var authManager: AuthManager = .shared

    // MARK: SwiftData container

    /// Shared ModelContainer for locally-cached timeline data.
    /// TODO: CachedStatus defined in Shared/SwiftData/CachedStatus.swift
    /// TODO: CachedActor  defined in Shared/SwiftData/CachedActor.swift
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            CachedStatus.self,
            CachedActor.self
        ])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // A production app would offer migration or graceful degradation.
            fatalError("Rosemount: Failed to create SwiftData ModelContainer — \(error)")
        }
    }()

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authManager)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: Deep-link handling

    /// Routes incoming URLs to the appropriate OAuth callback handler.
    ///
    /// Supported schemes:
    /// - `rosemount://oauth/mastodon`
    /// - `rosemount://oauth/pixelfed`
    ///
    /// Broadcasts a `Notification.Name("OAuthCallbackReceived")` carrying the full URL
    /// in the `userInfo` under the key `"url"`.  The listening `OnboardingViewModel`
    /// completes the OAuth exchange upon receipt.
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "rosemount" else { return }

        let supportedHosts = ["oauth"]
        guard let host = url.host, supportedHosts.contains(host) else { return }

        NotificationCenter.default.post(
            name: Notification.Name("OAuthCallbackReceived"),
            object: nil,
            userInfo: ["url": url]
        )
    }
}

// MARK: - RootView

/// Decides which top-level view to show based on authentication state.
private struct RootView: View {

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if authManager.isAuthenticated {
            // Defined in App/AppCoordinator.swift
            ContentView()
        } else {
            // Defined in Features/Onboarding/OnboardingView.swift
            OnboardingView()
        }
    }
}
