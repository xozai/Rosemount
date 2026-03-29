// AppCoordinator.swift
// Rosemount
//
// Root navigation structure shown when the user is authenticated.
// Contains the main TabView with seven tabs:
//
//   Tab 0 — Home           → HomeTimelineView
//                            (toolbar leading button → ConversationsView sheet)
//   Tab 1 — Communities    → CommunitiesView
//   Tab 2 — Events         → GlobalEventsView
//   Tab 3 — Photos         → PhotoFeedView  (Pixelfed accounts only)
//   Tab 4 — Explore        → ExploreView (search + trending hashtags)
//   Tab 5 — Notifications  → NotificationsView
//   Tab 6 — Profile        → ProfileView(accountId:)
//
//   Compose (New Post) is accessible via a toolbar button on the Home tab.
//
// Types referenced from other files:
//   HomeTimelineView    — Features/Feed/HomeTimelineView.swift
//   CommunitiesView     — Features/Communities/CommunitiesView.swift
//   ExploreView         — Features/Explore/ExploreView.swift
//   NotificationsView   — Features/Notifications/NotificationsView.swift
//   ProfileView         — Features/Profile/ProfileView.swift
//   PhotoComposeView    — Features/Photos/PhotoComposeView.swift
//   ConversationsView   — Features/Messaging/ConversationsView.swift
//   AuthManager         — Core/Auth/AuthManager.swift
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MARK: - Tab identifiers

private enum RosemountTab: Int, CaseIterable {
    case home          = 0
    case communities   = 1
    case events        = 2
    case photos        = 3
    case explore       = 4
    case notifications = 5
    case profile       = 6
}

// MARK: - ContentView

/// The root authenticated view containing the seven-tab navigation structure.
struct ContentView: View {

    // MARK: State

    @State private var selectedTab: Int = RosemountTab.home.rawValue
    @State private var showingCompose: Bool = false
    @State private var showingMessages: Bool = false
    @State private var deepLinkRouter = DeepLinkRouter.shared
    /// Deep-link profile/status presented modally over the current tab.
    @State private var deepLinkedProfileId: String? = nil
    @State private var deepLinkedStatusId: String? = nil

    @Environment(AuthManager.self) private var authManager

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {

            // 0. Home Timeline
            // HomeTimelineView already contains a NavigationStack.
            // Toolbar buttons for DMs and compose are injected here.
            HomeTimelineView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingMessages = true
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .accessibilityLabel("Direct Messages")
                        }
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingCompose = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .accessibilityLabel("New Post")
                        }
                    }
                }
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RosemountTab.home.rawValue)

            // 1. Communities
            NavigationStack {
                CommunitiesView()
            }
            .tabItem {
                Label("Communities", systemImage: "person.3")
            }
            .tag(RosemountTab.communities.rawValue)

            // 2. Events — global event discovery and RSVPs
            GlobalEventsView()
                .environment(authManager)
                .tabItem {
                    Label("Events", systemImage: "calendar")
                }
                .tag(RosemountTab.events.rawValue)

            // 3. Photos — Pixelfed photo feed
            PhotoFeedView()
                .environment(authManager)
                .tabItem {
                    Label("Photos", systemImage: "photo.stack")
                }
                .tag(RosemountTab.photos.rawValue)

            // 4. Explore — search + trending hashtags
            NavigationStack {
                ExploreView()
            }
            .tabItem {
                Label("Explore", systemImage: "magnifyingglass")
            }
            .tag(RosemountTab.explore.rawValue)

            // 5. Notifications
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(RosemountTab.notifications.rawValue)

            // 6. Profile
            // Pass the active account's Mastodon handle as the account identifier.
            // ProfileView uses this to look up the full account via the API.
            NavigationStack {
                ProfileView(accountId: authManager.activeAccount?.handle ?? "")
            }
            .tabItem {
                Label("Profile", systemImage: "person.circle")
            }
            .tag(RosemountTab.profile.rawValue)
        }
        // Photo-first compose sheet — triggered from the Home toolbar button.
        .sheet(isPresented: $showingCompose) {
            PhotoComposeView()
                .environment(authManager)
        }
        // Direct Messages sheet — accessible via the Home tab toolbar button.
        .sheet(isPresented: $showingMessages) {
            ConversationsView()
                .environment(authManager)
        }
        // Deep-link: profile
        .sheet(item: Binding(
            get: { deepLinkedProfileId.map { IdentifiableString($0) } },
            set: { deepLinkedProfileId = $0?.value }
        )) { wrapped in
            NavigationStack {
                ProfileView(accountId: wrapped.value)
            }
            .environment(authManager)
        }
        // Deep-link: status / post detail
        .sheet(item: Binding(
            get: { deepLinkedStatusId.map { IdentifiableString($0) } },
            set: { deepLinkedStatusId = $0?.value }
        )) { wrapped in
            DeepLinkPostDetailView(statusId: wrapped.value)
                .environment(authManager)
        }
        // React to DeepLinkRouter changes.
        .onChange(of: deepLinkRouter.pendingTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
        }
        .onChange(of: deepLinkRouter.pendingProfileId) { _, profileId in
            guard let profileId else { return }
            deepLinkedProfileId = profileId
            deepLinkRouter.pendingProfileId = nil
        }
        .onChange(of: deepLinkRouter.pendingStatusId) { _, statusId in
            guard let statusId else { return }
            deepLinkedStatusId = statusId
            deepLinkRouter.pendingStatusId = nil
        }
        .onChange(of: deepLinkRouter.pendingConversationId) { _, conversationId in
            guard conversationId != nil else { return }
            showingMessages = true
            deepLinkRouter.pendingConversationId = nil
        }
        // Consume any push-notification deep link queued before the view appeared.
        .onAppear {
            if let link = PushNotificationService.shared.consumePendingDeepLink() {
                DeepLinkRouter.shared.route(link,
                    homeTabIndex: RosemountTab.home.rawValue,
                    notificationsTabIndex: RosemountTab.notifications.rawValue)
            }
        }
    }
}

// MARK: - IdentifiableString helper

/// Wraps a `String` as `Identifiable` so it can be used with `.sheet(item:)`.
private struct IdentifiableString: Identifiable {
    let id = UUID()
    let value: String
}

// MARK: - DeepLinkPostDetailView

/// Fetches a status by ID and presents it in a `PostDetailView`.
/// Used when navigating to a post via a push notification or URL deep link.
private struct DeepLinkPostDetailView: View {
    let statusId: String
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var status: MastodonStatus? = nil
    @State private var isLoading: Bool = true
    @State private var error: Error? = nil

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let status {
                    PostDetailView(status: status)
                } else {
                    ContentUnavailableView("Post not found", systemImage: "bubble.left.and.bubble.right")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            guard let account = authManager.activeAccount else { isLoading = false; return }
            let client = MastodonAPIClient(instanceURL: account.instanceURL, accessToken: account.accessToken)
            do {
                status = try await client.fetchStatus(id: statusId)
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }
}
