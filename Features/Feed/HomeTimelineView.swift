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
            .navigationTitle("Home")
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
                // Trailing: filter / settings (stub)
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        // TODO: Phase 2 — timeline filter options
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
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
                                // TODO: Phase 2 — reply composer
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
            Text("Loading your feed…")
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

            Text("Couldn't load your feed")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
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
            "Your feed is empty",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("Follow some people to get started.")
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
