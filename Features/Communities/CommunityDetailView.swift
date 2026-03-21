// CommunityDetailView.swift
// Rosemount
//
// Community home screen: collapsible header, pinned posts, and a paginated feed.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// CommunityDetailViewModel — defined in Features/Communities/CommunityDetailViewModel.swift
// RosemountCommunity       — defined in Core/Communities/Models/RosemountCommunity.swift
// CommunityPinnedPost      — defined in Core/Communities/Models/CommunityMember.swift
// MastodonStatus           — defined in Core/Mastodon/Models/MastodonStatus.swift
// PostCardView             — defined in Shared/Components/PostCardView.swift
// AvatarView               — defined in Shared/Components/AvatarView.swift
// AuthManager              — defined in Core/Auth/AuthManager.swift
// ComposeView              — defined in Features/Compose/ComposeView.swift

// MARK: - CommunityDetailView

struct CommunityDetailView: View {

    // MARK: - Init

    let slug: String

    init(slug: String) {
        self.slug = slug
    }

    // MARK: - State

    @State private var viewModel = CommunityDetailViewModel()
    @Environment(AuthManager.self) private var authManager

    /// Controls the Leave confirmation dialog.
    @State private var showingLeaveConfirmation: Bool = false

    // MARK: - Body

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {

                // ── Community Header ──────────────────────────────────────
                if let community = viewModel.community {
                    CommunityHeaderView(community: community) {
                        Task {
                            if community.isMember {
                                showingLeaveConfirmation = true
                            } else {
                                await viewModel.join()
                            }
                        }
                    }
                } else if viewModel.isLoading {
                    headerPlaceholder
                }

                // ── Pinned Posts ──────────────────────────────────────────
                if !viewModel.pinnedPosts.isEmpty {
                    pinnedSection
                }

                // ── Feed ──────────────────────────────────────────────────
                if viewModel.isLoading && viewModel.feedStatuses.isEmpty {
                    feedLoadingPlaceholder
                } else if viewModel.feedStatuses.isEmpty && !viewModel.isLoading {
                    emptyFeedView
                } else {
                    feedSection
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationTitle(viewModel.community?.name ?? "Community")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $viewModel.showingPostComposer) {
            ComposeView()
                .environment(authManager)
        }
        .confirmationDialog(
            "Leave \(viewModel.community?.name ?? "Community")?",
            isPresented: $showingLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Community", role: .destructive) {
                Task { await viewModel.leave() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to request to rejoin if this is a private community.")
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
        .task {
            guard let account = authManager.activeAccount else { return }
            viewModel.setup(slug: slug, credential: account)
            await viewModel.refresh()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // Compose button (members only).
        if viewModel.canPost {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    viewModel.showingPostComposer = true
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .accessibilityLabel("New Post")
                }
            }
        }

        // Overflow menu.
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                // Leave option (members who are not the sole admin).
                if let community = viewModel.community, community.isMember {
                    Button(role: .destructive) {
                        showingLeaveConfirmation = true
                    } label: {
                        Label("Leave Community", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Members list.
                if let community = viewModel.community {
                    NavigationLink(value: CommunityNavigationDestination.members(slug: community.slug)) {
                        Label("Members", systemImage: "person.2")
                    }
                }

                // Settings (admins only).
                if viewModel.canManage, let community = viewModel.community {
                    NavigationLink(value: CommunityNavigationDestination.settings(slug: community.slug)) {
                        Label("Community Settings", systemImage: "gear")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .accessibilityLabel("More options")
            }
        }
    }

    // MARK: - Pinned Section

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header.
            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Pinned")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground))

            // Pinned post cards.
            ForEach(viewModel.pinnedPosts) { pinnedPost in
                PostCardView(status: pinnedPost.status)
            }

            Divider()
                .padding(.vertical, 4)
        }
    }

    // MARK: - Feed Section

    private var feedSection: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.feedStatuses) { status in
                PostCardView(status: status)

                // Trigger pagination when the last item appears.
                if status.id == viewModel.feedStatuses.last?.id {
                    Color.clear
                        .frame(height: 1)
                        .onAppear {
                            Task { await viewModel.loadMore() }
                        }
                }
            }

            // Load-more progress indicator.
            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Placeholder / Empty Views

    private var headerPlaceholder: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(maxWidth: .infinity)
                .frame(height: 180)

            Rectangle()
                .fill(Color(.systemBackground))
                .frame(height: 160)
        }
        .redacted(reason: .placeholder)
    }

    private var feedLoadingPlaceholder: some View {
        ProgressView()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var emptyFeedView: some View {
        ContentUnavailableView(
            "No Posts Yet",
            systemImage: "text.bubble",
            description: Text("Be the first to post in this community.")
        )
        .padding(.vertical, 40)
    }
}

// MARK: - CommunityNavigationDestination

/// Typed navigation values used by the community detail toolbar menu.
enum CommunityNavigationDestination: Hashable {
    case members(slug: String)
    case settings(slug: String)
}

// MARK: - CommunityHeaderView

/// The hero header displayed at the top of `CommunityDetailView`.
///
/// Shows the banner image, avatar, name, handle, description, member/post stats,
/// and action buttons (Join / Leave / Members / Settings).
struct CommunityHeaderView: View {

    // MARK: - Properties

    let community: RosemountCommunity

    /// Called when the user taps the Join or Leave button.
    var onJoinLeave: () -> Void

    // MARK: - Constants

    private let headerHeight: CGFloat = 180
    private let avatarSize:   CGFloat = 72
    private let avatarOverlap: CGFloat = 20

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // ── Banner Image ──────────────────────────────────────────────
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: community.headerImageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(maxWidth: .infinity)
                            .frame(height: headerHeight)
                            .clipped()
                            .transition(.opacity.animation(.easeIn(duration: 0.2)))
                    case .empty, .failure:
                        headerPlaceholderGradient
                    @unknown default:
                        headerPlaceholderGradient
                    }
                }
                .frame(height: headerHeight)
            }

            // ── Avatar + Info ─────────────────────────────────────────────
            VStack(alignment: .leading, spacing: 10) {

                // Avatar (overlaps the banner by avatarOverlap points).
                AvatarView(
                    url: community.avatarImageURL,
                    size: avatarSize,
                    shape: .roundedSquare
                )
                .offset(y: -avatarOverlap)
                .padding(.bottom, -avatarOverlap)

                // Name row.
                HStack(spacing: 6) {
                    Text(community.name)
                        .font(.title3)
                        .fontWeight(.bold)
                        .lineLimit(2)

                    if community.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .labelStyle(.iconOnly)
                    }
                }

                // ActivityPub handle.
                Text("@\(community.slug)@\(community.instanceHost)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                // Description.
                if !community.description.isEmpty {
                    Text(community.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Stats row.
                HStack(spacing: 20) {
                    statLabel(value: community.memberCount, label: "Members")
                    statLabel(value: community.postCount,   label: "Posts")
                }

                // Private badge.
                if community.isPrivate {
                    Label("Private community", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.secondary.opacity(0.7), in: Capsule())
                }

                // Action buttons row.
                actionButtons
            }
            .padding(.horizontal, 16)
            .padding(.top, avatarOverlap + 4)
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Action Buttons

    @ViewBuilder
    private var actionButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {

                // Join / Leave button.
                if !community.isMember {
                    Button(action: onJoinLeave) {
                        Text(community.isPrivate ? "Request to Join" : "Join")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color.accentColor, in: Capsule())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                } else if !community.isAdmin {
                    Button(action: onJoinLeave) {
                        Text("Leave")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }

                // Members list button.
                NavigationLink(value: CommunityNavigationDestination.members(slug: community.slug)) {
                    Text("Members")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(Color(.systemGray5), in: Capsule())
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)

                // Settings button (admins only).
                if community.isAdmin {
                    NavigationLink(value: CommunityNavigationDestination.settings(slug: community.slug)) {
                        Label("Settings", systemImage: "gear")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                            .background(Color(.systemGray5), in: Capsule())
                            .foregroundStyle(.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Subview Helpers

    private var headerPlaceholderGradient: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.2)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: headerHeight)
    }

    @ViewBuilder
    private func statLabel(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(compactCount(value))
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
#Preview("CommunityDetailView") {
    NavigationStack {
        CommunityDetailView(slug: "softball-league")
            .environment(AuthManager.shared)
    }
}
#endif
