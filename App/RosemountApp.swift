// RosemountApp.swift
// Rosemount
//
// @main SwiftUI App entry point.
// Sets up SwiftData ModelContainer, injects AuthManager into the environment,
// routes between ContentView and OnboardingView, and handles OAuth deep-link callbacks.
//
// Swift 5.10 | iOS 17.0+

import MetricKit
import OSLog
import SwiftUI
import SwiftData
import UserNotifications

private let logger = Logger(subsystem: "social.rosemount", category: "AppDelegate")

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundSyncService.registerTasks()
        MetricKitReporter.shared.start()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error {
                logger.error("Push authorisation request failed: \(error.localizedDescription)")
                return
            }
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
        logger.debug("Received APNs device token (\(deviceToken.count) bytes)")
        Task { await PushNotificationService.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("Failed to register for remote notifications: \(error.localizedDescription)")
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

    /// Whether the persistent store failed and we are running on an in-memory fallback.
    /// When `true` a banner is shown so the user knows data will not persist across launches.
    @State private var isUsingMemoryFallback: Bool = false

    /// Shared ModelContainer for locally-cached timeline data.
    /// CachedStatus — defined in Shared/SwiftData/CachedStatus.swift
    /// CachedActor  — defined in Shared/SwiftData/CachedActor.swift
    private let modelContainer: ModelContainer = {
        let schema = Schema([
            CachedStatus.self,
            CachedActor.self
        ])

        // Attempt persistent store first.
        let persistentConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )
        if let container = try? ModelContainer(for: schema, configurations: [persistentConfig]) {
            return container
        }

        // Persistent store failed (e.g. migration issue). Fall back to in-memory so the
        // app remains usable; the banner in RootView will inform the user.
        let logger = Logger(subsystem: "social.rosemount", category: "SwiftData")
        logger.error("Persistent ModelContainer unavailable — falling back to in-memory store.")
        let memoryConfig = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [memoryConfig])
        } catch {
            // Even in-memory failed — this indicates a code-level schema error.
            fatalError("Rosemount: Could not create even an in-memory ModelContainer — \(error)")
        }
    }()

    // MARK: Scene

    var body: some Scene {
        WindowGroup {
            RootView(isUsingMemoryFallback: $isUsingMemoryFallback)
                .environment(authManager)
                .modelContainer(modelContainer)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
    }

    // MARK: Deep-link handling

    /// Routes incoming `rosemount://` URLs.
    ///
    /// Supported paths:
    /// - `rosemount://oauth/mastodon`  → OAuth callback
    /// - `rosemount://oauth/pixelfed`  → OAuth callback
    /// - `rosemount://profile/<accountId>` → Open profile (via DeepLinkRouter)
    /// - `rosemount://status/<statusId>`   → Open post detail (via DeepLinkRouter)
    /// - `rosemount://conversation/<conversationId>` → Open DM thread (via DeepLinkRouter)
    /// - `rosemount://notifications`       → Switch to notifications tab (via DeepLinkRouter)
    @MainActor
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "rosemount" else { return }
        guard let host = url.host else { return }

        if host == "oauth" {
            // Notify OnboardingViewModel to complete the OAuth exchange.
            NotificationCenter.default.post(
                name: Notification.Name("OAuthCallbackReceived"),
                object: nil,
                userInfo: ["url": url]
            )
        } else {
            // All other deep links are routed through the observable DeepLinkRouter
            // so that AppCoordinator can react to them via @Observable change tracking.
            DeepLinkRouter.shared.route(url: url)
        }
    }
}

// MARK: - RootView

/// Decides which top-level view to show based on authentication state.
private struct RootView: View {

    @Environment(AuthManager.self) private var authManager
    @Binding var isUsingMemoryFallback: Bool

    var body: some View {
        ZStack(alignment: .bottom) {
            if authManager.isAuthenticated {
                ContentView()
            } else {
                OnboardingView()
            }

            if isUsingMemoryFallback {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Cache unavailable — posts won't be saved offline.")
                        .font(.caption)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
}
