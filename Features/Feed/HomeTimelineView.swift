// HomeTimelineView.swift
// Rosemount
//
// The home timeline feed view — shows statuses from accounts the user follows.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonStatus        — defined in Core/Mastodon/Models/MastodonStatus.swift
// AuthManager           — defined in Core/Auth/AuthManager.swift
// AccountCredential     — defined in Core/Auth/AuthManager.swift
// HomeTimelineViewModel — defined in Features/Feed/HomeTimelineViewModel.swift
// PostCardView          — defined in Shared/Components/PostCardView.swift
// AvatarView            — defined in Shared/Components/AvatarView.swift
// PostDetailView        — defined in Features/Profile/PostDetailView.swift
// NetworkMonitor        — defined in Core/Offline/NetworkMonitor.swift

// MARK: - HomeTimelineView

struct HomeTimelineView: View {

    // MARK: - State

    @State private var viewModel = HomeTimelineViewModel()
    @State private var storiesViewModel = StoriesViewModel()
    @State private var replyingTo: MastodonStatus? = nil
    @State private var viewingStoryGroup: StoryGroup? = nil
    @State private var showingStoryComposer = false
    @Environment(AuthManager.self) private var authManager
    @State private var networkMonitor = NetworkMonitor.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if !networkMonitor.isConnected && viewModel.statuses.isEmpty {
                    offlineView
                } else if viewModel.isLoading && viewModel.statuses.isEmpty {
                    loadingView
                } else if let error = viewModel.error, viewModel.statuses.isEmpty {
                    errorView(error)
                } else if viewModel.statuses.isEmpty {
                    emptyView
                } else {
                    timelineList
                }
            }
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    let storyGroups = viewModel.isDemoMode
                        ? HomeTimelineView.demoStoryGroups
                        : storiesViewModel.allGroups
                    StoriesRowView(
                        groups: storyGroups,
                        onTap: { group in viewingStoryGroup = group },
                        onAddStory: { showingStoryComposer = true }
                    )
                    .environment(authManager)
                    Divider()
                    if viewModel.isDemoMode {
                        HStack(spacing: 6) {
                            Image(systemName: "eyes")
                            Text("Demo Mode — App Review")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.yellow, in: Capsule())
                        .padding(.top, 4)
                    }
                }
                .background(.background)
            }
            .navigationTitle(String(localized: "tab.home"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Leading: current account avatar
                ToolbarItem(placement: .navigationBarLeading) {
                    if let account = authManager.activeAccount {
                        AvatarView(
                            url: account.avatarURL,
                            size: 30,
                            shape: .circle
                        )
                    }
                }
                // Trailing: feed type filter
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        ForEach(FeedType.allCases, id: \.self) { type in
                            Button {
                                Task { await viewModel.switchFeed(to: type) }
                            } label: {
                                Label(type.rawValue, systemImage: type.icon)
                            }
                        }
                    } label: {
                        Image(systemName: viewModel.feedType == .home
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .accessibilityLabel("Feed filter: \(viewModel.feedType.rawValue)")
                    }
                }
            }
        }
        .task {
            guard let account = authManager.activeAccount else { return }
            viewModel.setup(with: account)
            storiesViewModel.setup(with: account)
            await viewModel.refresh()
            if !viewModel.isDemoMode {
                await storiesViewModel.refresh()
            }
        }
        .onChange(of: authManager.activeAccount) { _, newAccount in
            guard let newAccount else { return }
            Task {
                viewModel.setup(with: newAccount)
                storiesViewModel.setup(with: newAccount)
                await viewModel.refresh()
                if !viewModel.isDemoMode {
                    await storiesViewModel.refresh()
                }
            }
        }
        // Reply composer sheet
        .sheet(item: $replyingTo) { status in
            ComposeView(replyTo: status)
                .environment(authManager)
        }
        // Story viewer
        .fullScreenCover(item: $viewingStoryGroup) { group in
            let startIndex = storiesViewModel.allGroups.firstIndex(of: group) ?? 0
            StoryViewerView(
                groups: viewModel.isDemoMode ? HomeTimelineView.demoStoryGroups : storiesViewModel.allGroups,
                startingGroupIndex: startIndex
            )
            .environment(authManager)
        }
        // Story composer
        .sheet(isPresented: $showingStoryComposer) {
            StoryComposerView()
                .environment(authManager)
                .onDisappear {
                    guard let account = authManager.activeAccount else { return }
                    storiesViewModel.setup(with: account)
                    Task { await storiesViewModel.refresh() }
                }
        }
        // Show errors that occur after content is already loaded (e.g. rate-limit during pagination or action).
        .alert(
            String(localized: "error.title"),
            isPresented: Binding(
                get: { viewModel.error != nil && !viewModel.statuses.isEmpty },
                set: { if !$0 { viewModel.error = nil } }
            )
        ) {
            Button(String(localized: "error.dismiss"), role: .cancel) { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Subviews

    /// The main scrollable timeline list.
    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(viewModel.statuses) { status in
                    NavigationLink(value: status) {
                        PostCardView(
                            status: status,
                            onTap: nil,         // NavigationLink handles tap
                            onFavourite: {
                                Task { await viewModel.toggleFavourite(status) }
                            },
                            onBoost: {
                                Task { await viewModel.boost(status) }
                            },
                            onReply: {
                                replyingTo = status
                            }
                        )
                        .tint(.primary)
                    }
                    .buttonStyle(.plain)

                    // Infinite scroll trigger: load more when the last item appears.
                    if status.id == viewModel.statuses.last?.id {
                        loadMoreTrigger
                    }
                }

                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
        .refreshable {
            await viewModel.refresh()
        }
        .navigationDestination(for: MastodonStatus.self) { status in
            PostDetailView(status: status)
        }
    }

    /// Invisible view at the bottom of the list that triggers pagination when it appears.
    private var loadMoreTrigger: some View {
        Color.clear
            .frame(height: 1)
            .onAppear {
                Task { await viewModel.loadMore() }
            }
    }

    /// Full-screen offline empty state shown when there is no network and no cached content.
    private var offlineView: some View {
        ContentUnavailableView(
            String(localized: "offline.title"),
            systemImage: "wifi.slash",
            description: Text(String(localized: "offline.subtitle"))
        )
    }

    /// Full-screen loading indicator shown on the initial fetch.
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text(String(localized: "timeline.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Full-screen error state with a retry button.
    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(String(localized: "error.feed.load_failed"))
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button(String(localized: "timeline.error.retry")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    /// Full-screen empty state shown when the timeline has no statuses.
    private var emptyView: some View {
        ContentUnavailableView(
            String(localized: "timeline.empty.title"),
            systemImage: "bubble.left.and.bubble.right",
            description: Text(String(localized: "timeline.empty.subtitle"))
        )
    }
}

// MARK: - Demo Helpers

private extension HomeTimelineView {
    static var demoStoryGroups: [StoryGroup] {
        func makeAccount(id: String, name: String, handle: String) -> MastodonAccount {
            MastodonAccount(
                id: id, username: handle, acct: handle, displayName: name,
                locked: false, bot: false,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                note: "", url: "", avatar: "", avatarStatic: "",
                header: "", headerStatic: "",
                followersCount: 0, followingCount: 0, statusesCount: 0,
                emojis: [], fields: []
            )
        }
        func makeStory(id: String, account: MastodonAccount) -> RosemountStory {
            let iso = ISO8601DateFormatter()
            return RosemountStory(
                id: id, account: account,
                mediaURL: "", mediaType: .image, duration: 5,
                caption: nil, backgroundColor: "#4A90D9",
                createdAt: iso.string(from: Date()),
                expiresAt: iso.string(from: Date().addingTimeInterval(86400)),
                viewCount: 0, hasViewed: false, reactions: []
            )
        }
        let a1 = makeAccount(id: "demo-story-1", name: "Alice", handle: "alice")
        let a2 = makeAccount(id: "demo-story-2", name: "Bob", handle: "bob")
        let a3 = makeAccount(id: "demo-story-3", name: "Carol", handle: "carol")
        return [
            StoryGroup(account: a1, stories: [makeStory(id: "ds1", account: a1)]),
            StoryGroup(account: a2, stories: [makeStory(id: "ds2", account: a2)]),
            StoryGroup(account: a3, stories: [makeStory(id: "ds3", account: a3)]),
        ]
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    HomeTimelineView()
        .environment(AuthManager.shared)
}
#endif
