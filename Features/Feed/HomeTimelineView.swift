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

// MARK: - HomeTimelineView

struct HomeTimelineView: View {

    // MARK: - State

    @State private var viewModel = HomeTimelineViewModel()
    @State private var replyingTo: MastodonStatus? = nil
    @Environment(AuthManager.self) private var authManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.statuses.isEmpty {
                    loadingView
                } else if let error = viewModel.error, viewModel.statuses.isEmpty {
                    errorView(error)
                } else if viewModel.statuses.isEmpty {
                    emptyView
                } else {
                    timelineList
                }
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
            await viewModel.refresh()
        }
        .onChange(of: authManager.activeAccount) { _, newAccount in
            guard let newAccount else { return }
            Task {
                viewModel.setup(with: newAccount)
                await viewModel.refresh()
            }
        }
        // Reply composer sheet
        .sheet(item: $replyingTo) { status in
            ComposeView(replyTo: status)
                .environment(authManager)
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

// MARK: - Previews

#if DEBUG
#Preview {
    HomeTimelineView()
        .environment(AuthManager.shared)
}
#endif
