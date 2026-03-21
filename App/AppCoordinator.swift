// AppCoordinator.swift
// Rosemount
//
// Root navigation structure shown when the user is authenticated.
// Contains the main TabView with five tabs:
//
//   Tab 0 — Home           → HomeTimelineView
//                            (toolbar leading button → ConversationsView sheet)
//   Tab 1 — Communities    → CommunitiesView
//   Tab 2 — Compose        → presents PhotoComposeView as a sheet (no inline view)
//   Tab 3 — Notifications  → NotificationsView
//   Tab 4 — Profile        → ProfileView(accountId:)
//
// Types referenced from other files:
//   HomeTimelineView    — Features/Feed/HomeTimelineView.swift
//   CommunitiesView     — Features/Communities/CommunitiesView.swift
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
    @State private var showingMessages: Bool = false

    @Environment(AuthManager.self) private var authManager

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {

            // 0. Home Timeline
            // HomeTimelineView already contains a NavigationStack.
            // We add a leading toolbar button for DMs via a modifier that
            // injects into the inner NavigationStack's toolbar.
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

            // 2. Compose — centre tab.
            // A transparent placeholder so the tab item renders; the sheet
            // is presented modally via .onChange below.
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
        // Intercept the compose tab to present PhotoComposeView as a sheet,
        // then revert the selection so dismissal doesn't leave compose "active".
        .onChange(of: selectedTab) { _, newValue in
            if newValue == RosemountTab.compose.rawValue {
                showingCompose = true
                selectedTab = RosemountTab.home.rawValue
            }
        }
        // Photo-first compose sheet (Phase 2).
        .sheet(isPresented: $showingCompose) {
            PhotoComposeView()
                .environment(authManager)
        }
        // Direct Messages sheet — accessible via the Home tab toolbar button.
        .sheet(isPresented: $showingMessages) {
            ConversationsView()
                .environment(authManager)
        }
    }
}
