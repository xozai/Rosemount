// AppCoordinator.swift
// Rosemount
//
// Root navigation structure shown when the user is authenticated.
// Contains the main TabView (ContentView) and the updated Phase 2 navigation wiring:
//
//   Tab 0 — Home           → HomeTimelineView  (with DM toolbar button → ConversationsView)
//   Tab 1 — Communities    → CommunitiesPlaceholderView  (Phase 3)
//   Tab 2 — Compose        → presents PhotoComposeView sheet (no inline view)
//   Tab 3 — Notifications  → NotificationsView  (Phase 2)
//   Tab 4 — Profile        → ProfileView(accountId:)  (Phase 2)
//
// Types referenced from other files:
//   HomeTimelineView        — Features/Feed/HomeTimelineView.swift
//   NotificationsView       — Features/Notifications/NotificationsView.swift
//   ProfileView             — Features/Profile/ProfileView.swift
//   PhotoComposeView        — Features/Compose/PhotoComposeView.swift
//   ConversationsView       — Features/Messages/ConversationsView.swift
//   AuthManager             — Core/Auth/AuthManager.swift
//   AvatarView              — Shared/Components/AvatarView.swift
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MARK: - Tab identifiers

private enum RosemountTab: Int, CaseIterable {
    case home          = 0
    case communities   = 1
    case compose       = 2
    case notifications = 3
    case profile       = 4
}

// MARK: - ContentView

/// The root authenticated view containing the five-tab navigation structure.
struct ContentView: View {

    // MARK: State

    @State private var selectedTab: Int = RosemountTab.home.rawValue
    @State private var showingCompose: Bool = false

    @Environment(AuthManager.self) private var authManager

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {

            // 0. Home Timeline
            homeTab
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RosemountTab.home.rawValue)

            // 1. Communities — Phase 3 placeholder
            CommunitiesPlaceholderView()
                .tabItem {
                    Label("Communities", systemImage: "person.3")
                }
                .tag(RosemountTab.communities.rawValue)

            // 2. Compose — centre tab, presented as a sheet.
            // A transparent view acts as the tab-bar placeholder so the tab
            // item renders correctly; actual content is modal.
            Color.clear
                .tabItem {
                    Label("New Post", systemImage: "plus.circle.fill")
                }
                .tag(RosemountTab.compose.rawValue)

            // 3. Notifications
            NotificationsView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(RosemountTab.notifications.rawValue)

            // 4. Profile
            ProfileView(accountId: authManager.activeAccount?.handle ?? "")
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
                .tag(RosemountTab.profile.rawValue)
        }
        // Intercept the compose tab so tapping it shows the sheet rather than
        // navigating to an empty screen.
        .onChange(of: selectedTab) { _, newValue in
            if newValue == RosemountTab.compose.rawValue {
                showingCompose = true
                // Revert so dismissing the sheet does not leave compose "active".
                selectedTab = RosemountTab.home.rawValue
            }
        }
        // Photo-first compose sheet (Phase 2).
        .sheet(isPresented: $showingCompose) {
            PhotoComposeView()
                .environment(authManager)
        }
    }

    // MARK: - Home tab (with DM toolbar button)

    /// Wraps HomeTimelineView in a NavigationStack that adds a messages button
    /// in the toolbar, giving easy access to ConversationsView without occupying
    /// a dedicated tab.
    private var homeTab: some View {
        NavigationStack {
            HomeTimelineView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        NavigationLink {
                            ConversationsView()
                        } label: {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .accessibilityLabel("Direct Messages")
                        }
                    }
                }
        }
    }
}

// MARK: - CommunitiesPlaceholderView

/// Phase 3 placeholder for the Communities tab.
struct CommunitiesPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Communities — Coming Soon")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Community spaces and local timelines\nare coming in Phase 3.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - PostDetailPlaceholderView

/// Legacy stub destination kept for source compatibility.
/// Phase 2 supersedes this with PostDetailView.
struct PostDetailPlaceholderView: View {
    let statusId: String

    var body: some View {
        ContentUnavailableView(
            "Thread View",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Full thread view is coming in Phase 2.")
        )
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
    }
}
