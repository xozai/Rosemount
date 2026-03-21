// AppCoordinator.swift
// Rosemount
//
// Root navigation structure shown when the user is authenticated.
// Contains the main TabView (ContentView) plus placeholder and profile views.
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
    @State private var showCompose: Bool = false

    @Environment(AuthManager.self) private var authManager

    // MARK: Body

    var body: some View {
        TabView(selection: $selectedTab) {

            // 1. Home Timeline
            // Defined in Features/Feed/HomeTimelineView.swift
            HomeTimelineView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(RosemountTab.home.rawValue)

            // 2. Communities — Phase 3 placeholder
            CommunitiesPlaceholderView()
                .tabItem {
                    Label("Communities", systemImage: "person.3")
                }
                .tag(RosemountTab.communities.rawValue)

            // 3. Compose — centre tab, presented as a sheet
            // We use a transparent placeholder so the tab item renders correctly;
            // the actual compose sheet is presented modally.
            Color.clear
                .tabItem {
                    Label("New Post", systemImage: "plus.circle.fill")
                }
                .tag(RosemountTab.compose.rawValue)

            // 4. Notifications — Phase 2 placeholder
            NotificationsPlaceholderView()
                .tabItem {
                    Label("Notifications", systemImage: "bell")
                }
                .tag(RosemountTab.notifications.rawValue)

            // 5. Profile
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
                .tag(RosemountTab.profile.rawValue)
        }
        // Intercept compose tab selection to present the sheet instead.
        .onChange(of: selectedTab) { _, newValue in
            if newValue == RosemountTab.compose.rawValue {
                showCompose = true
                // Revert selection so the sheet dismissal doesn't leave compose "active".
                selectedTab = RosemountTab.home.rawValue
            }
        }
        // Compose sheet
        // Defined in Features/Compose/ComposeView.swift
        .sheet(isPresented: $showCompose) {
            ComposeView()
                .environment(authManager)
        }
    }
}

// MARK: - ProfileView

/// Displays the currently active account's basic information.
struct ProfileView: View {

    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            Group {
                if let account = authManager.activeAccount {
                    VStack(spacing: 20) {
                        // Avatar
                        // Defined in Shared/Components/AvatarView.swift
                        AvatarView(url: account.avatarURL, size: 80, shape: .circle)

                        VStack(spacing: 4) {
                            Text(account.displayName ?? account.handle)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("@\(account.handle)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        Text(account.instanceURL.host ?? account.instanceURL.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())

                        Spacer()

                        // Sign out
                        Button(role: .destructive) {
                            authManager.signOut()
                        } label: {
                            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 40)
                } else {
                    ContentUnavailableView(
                        "No Account",
                        systemImage: "person.circle",
                        description: Text("Sign in to view your profile.")
                    )
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
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

// MARK: - NotificationsPlaceholderView

/// Placeholder for the Notifications tab until Phase 2.
struct NotificationsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.secondary)

                Text("Notifications — Coming Soon")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text("Push notifications and activity alerts\nare coming in Phase 2.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

// MARK: - PostDetailPlaceholderView

/// Stub destination for tapping a post in the timeline.
struct PostDetailPlaceholderView: View {
    // MastodonStatus defined in Core/Mastodon/Models/MastodonStatus.swift
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
