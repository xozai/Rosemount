// CommunitiesView.swift
// Rosemount
//
// Main Communities tab — joined communities, discovery, search, join/leave.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// CommunitiesViewModel  — defined in Features/Communities/CommunitiesViewModel.swift
// CommunityDetailView   — defined in Features/Communities/CommunityDetailView.swift
// CreateCommunityView   — defined in Features/Communities/CreateCommunityView.swift
// RosemountCommunity    — defined in Core/Communities/Models/RosemountCommunity.swift
// CommunityRole         — defined in Core/Communities/Models/RosemountCommunity.swift
// AuthManager           — defined in Core/Auth/AuthManager.swift
// AvatarView            — defined in Shared/Components/AvatarView.swift
// NetworkMonitor        — defined in Core/Offline/NetworkMonitor.swift

// MARK: - CommunitiesView

struct CommunitiesView: View {

    // MARK: - State

    @State private var viewModel = CommunitiesViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var networkMonitor = NetworkMonitor.shared

    @State private var showingCreate: Bool = false
    @State private var selectedCommunity: RosemountCommunity? = nil

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !networkMonitor.isConnected && viewModel.joinedCommunities.isEmpty && viewModel.discoveredCommunities.isEmpty {
                    ContentUnavailableView(
                        String(localized: "offline.title"),
                        systemImage: "wifi.slash",
                        description: Text(String(localized: "offline.subtitle"))
                    )
                } else if viewModel.isLoading && viewModel.joinedCommunities.isEmpty && viewModel.discoveredCommunities.isEmpty {
                    loadingView
                } else {
                    communityContent
                }
            }
            .navigationTitle("Communities")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Create Community")
                    }
                }
            }
            // Navigation destination for tapping a community row.
            .navigationDestination(for: RosemountCommunity.self) { community in
                CommunityDetailView(slug: community.slug)
            }
            .sheet(isPresented: $showingCreate) {
                CreateCommunityView()
                    .environment(authManager)
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
        .task {
            guard let account = authManager.activeAccount else { return }
            viewModel.setup(with: account)
            await viewModel.refresh()
        }
        .onChange(of: authManager.activeAccount) { _, newAccount in
            guard let newAccount else { return }
            Task {
                viewModel.setup(with: newAccount)
                await viewModel.refresh()
            }
        }
        .onChange(of: viewModel.searchQuery) { _, _ in
            Task { await viewModel.search() }
        }
    }

    // MARK: - Main Content

    private var communityContent: some View {
        VStack(spacing: 0) {
            // Segmented control tab picker.
            Picker("Communities", selection: $viewModel.selectedTab) {
                ForEach(CommunityTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Content area switches on selected tab.
            Group {
                switch viewModel.selectedTab {
                case .joined:
                    joinedList
                case .discover:
                    discoverList
                }
            }
            .searchable(
                text: $viewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: viewModel.selectedTab == .discover
                    ? "Search communities…"
                    : "Filter joined communities…"
            )
        }
    }

    // MARK: - Joined List

    private var joinedList: some View {
        Group {
            if viewModel.joinedCommunities.isEmpty {
                emptyJoinedView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredJoined) { community in
                            NavigationLink(value: community) {
                                CommunityRowView(community: community)
                                    .tint(.primary)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
    }

    /// Filters the joined communities by the current search query when on the joined tab.
    private var filteredJoined: [RosemountCommunity] {
        let q = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return viewModel.joinedCommunities }
        return viewModel.joinedCommunities.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    // MARK: - Discover List

    private var discoverList: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.discoveredCommunities.isEmpty {
                emptyDiscoverView
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.discoveredCommunities) { community in
                            NavigationLink(value: community) {
                                CommunityRowView(community: community) {
                                    Task { await viewModel.join(community) }
                                }
                                .tint(.primary)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .padding(.leading, 76)
                        }
                    }
                }
                .refreshable {
                    await viewModel.refresh()
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyJoinedView: some View {
        ContentUnavailableView(
            "No Communities Yet",
            systemImage: "person.3",
            description: Text("You haven't joined any communities yet.\nSwitch to Discover to find one.")
        )
        .frame(maxHeight: .infinity)
    }

    private var emptyDiscoverView: some View {
        let hasQuery = !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return ContentUnavailableView(
            hasQuery ? "No Results" : "No Communities Found",
            systemImage: hasQuery ? "magnifyingglass" : "person.3",
            description: Text(
                hasQuery
                    ? "No communities matched \"\(viewModel.searchQuery)\". Try a different search."
                    : "There are no public communities to discover right now."
            )
        )
        .frame(maxHeight: .infinity)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading communities…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - CommunityRowView

/// A single row representing one community in either the joined or discover list.
struct CommunityRowView: View {

    // MARK: - Properties

    let community: RosemountCommunity

    /// When non-nil, displays a Join button (used in the discover list).
    var onJoin: (() -> Void)?

    // MARK: - Init

    init(community: RosemountCommunity, onJoin: (() -> Void)? = nil) {
        self.community = community
        self.onJoin    = onJoin
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .center, spacing: 12) {

            // Community avatar.
            AvatarView(
                url: community.avatarImageURL,
                size: 50,
                shape: .roundedSquare
            )

            // Name + description + stats column.
            VStack(alignment: .leading, spacing: 3) {
                // Name row with optional lock icon.
                HStack(spacing: 4) {
                    Text(community.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)

                    if community.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // One-line description.
                if !community.description.isEmpty {
                    Text(community.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Member + post counts.
                HStack(spacing: 8) {
                    Label {
                        Text(compactCount(community.memberCount))
                    } icon: {
                        Image(systemName: "person.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Label {
                        Text(compactCount(community.postCount))
                    } icon: {
                        Image(systemName: "text.bubble")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            // Trailing action area: Join button OR role badge.
            if let onJoin, !community.isMember {
                Button(action: onJoin) {
                    Text("Join")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else if community.isMember, let role = community.myRole {
                roleBadge(for: role)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Role Badge

    @ViewBuilder
    private func roleBadge(for role: CommunityRole) -> some View {
        Text(role.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(badgeColor(for: role).opacity(0.15), in: Capsule())
            .foregroundStyle(badgeColor(for: role))
    }

    private func badgeColor(for role: CommunityRole) -> Color {
        switch role {
        case .admin:     return .purple
        case .moderator: return .blue
        case .member:    return .secondary
        }
    }

    // MARK: - Helpers

    /// Formats an integer count compactly: 1 000 → "1k", 1 000 000 → "1M".
    private func compactCount(_ n: Int) -> String {
        switch n {
        case ..<1_000:
            return "\(n)"
        case ..<1_000_000:
            let val = Double(n) / 1_000
            return val.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fk", val)
                : String(format: "%.1fk", val)
        default:
            let val = Double(n) / 1_000_000
            return val.truncatingRemainder(dividingBy: 1) == 0
                ? String(format: "%.0fM", val)
                : String(format: "%.1fM", val)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CommunitiesView") {
    CommunitiesView()
        .environment(AuthManager.shared)
}
#endif
