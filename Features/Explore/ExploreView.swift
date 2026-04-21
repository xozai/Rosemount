// ExploreView.swift
// Rosemount
//
// Explore tab: trending hashtags shown by default; full search (accounts,
// statuses, hashtags) when the user types in the search bar.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// ExploreViewModel      — defined in Features/Explore/ExploreViewModel.swift
// MastodonTag           — defined in Core/Mastodon/Models/MastodonStatus.swift
// MastodonSearchResults — defined in Core/Mastodon/MastodonAPIClient.swift
// AuthManager           — defined in Core/Auth/AuthManager.swift
// PostCardView          — defined in Shared/Components/PostCardView.swift
// AvatarView            — defined in Shared/Components/AvatarView.swift
// PostDetailView        — defined in Features/Profile/PostDetailView.swift

// MARK: - ExploreView

struct ExploreView: View {

    // MARK: - State

    @State private var viewModel = ExploreViewModel()
    @Environment(AuthManager.self) private var authManager

    // MARK: - Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "tab.explore"))
                .navigationBarTitleDisplayMode(.large)
                .searchable(
                    text: $viewModel.searchQuery,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: String(localized: "explore.search.prompt")
                )
                .sheet(item: $viewModel.replyTarget) { target in
                    ComposeView(replyTo: target)
                }
                .onChange(of: viewModel.searchQuery) { _, newValue in
                    viewModel.onQueryChanged(newValue)
                }
                .onSubmit(of: .search) {
                    Task { await viewModel.performSearch(query: viewModel.searchQuery) }
                }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.loadTrendingTags()
        }
    }

    // MARK: - Content Dispatch

    @ViewBuilder
    private var content: some View {
        let trimmed = viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trendingContent
        } else if viewModel.isLoading && viewModel.searchResults == nil {
            searchLoadingView
        } else if let results = viewModel.searchResults {
            searchResultsView(results)
        } else {
            searchLoadingView
        }
    }

    // MARK: - Trending

    @ViewBuilder
    private var trendingContent: some View {
        if viewModel.isTrendingLoading {
            VStack {
                Spacer()
                ProgressView()
                Spacer()
            }
        } else if viewModel.trendingTags.isEmpty {
            ContentUnavailableView(
                String(localized: "explore.trending.empty.title"),
                systemImage: "number",
                description: Text(String(localized: "explore.trending.empty.subtitle"))
            )
        } else {
            List {
                Section {
                    ForEach(viewModel.trendingTags, id: \.name) { tag in
                        NavigationLink(value: tag) {
                            TrendingTagRow(tag: tag)
                        }
                    }
                } header: {
                    Text(String(localized: "explore.section.trending"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: MastodonTag.self) { tag in
                HashtagFeedView(hashtag: tag.name)
            }
        }
    }

    // MARK: - Search Loading

    private var searchLoadingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.2)
            Text(String(localized: "explore.search.loading"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Search Results

    @ViewBuilder
    private func searchResultsView(_ results: MastodonSearchResults) -> some View {
        if results.accounts.isEmpty && results.statuses.isEmpty && results.hashtags.isEmpty {
            ContentUnavailableView.search(text: viewModel.searchQuery)
        } else {
            List {
                // Accounts section
                if !results.accounts.isEmpty {
                    Section {
                        ForEach(results.accounts) { account in
                            NavigationLink(value: account) {
                                AccountSearchRow(account: account)
                            }
                        }
                    } header: {
                        Text(String(localized: "explore.section.accounts"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }

                // Hashtags section
                if !results.hashtags.isEmpty {
                    Section {
                        ForEach(results.hashtags, id: \.name) { tag in
                            NavigationLink(value: tag) {
                                TrendingTagRow(tag: tag)
                            }
                        }
                    } header: {
                        Text(String(localized: "explore.section.hashtags"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }

                // Statuses section
                if !results.statuses.isEmpty {
                    Section {
                        ForEach(results.statuses) { status in
                            NavigationLink(value: status) {
                                PostCardView(
                                    status: status,
                                    onTap: nil,
                                    onFavourite: { Task { await viewModel.toggleFavourite(status) } },
                                    onBoost:     { Task { await viewModel.boost(status) } },
                                    onReply:     { viewModel.replyTarget = status }
                                )
                                .tint(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(String(localized: "explore.section.posts"))
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: MastodonTag.self) { tag in
                HashtagFeedView(hashtag: tag.name)
            }
            .navigationDestination(for: MastodonAccount.self) { account in
                NavigationStack {
                    ProfileView(accountId: account.id)
                }
            }
            .navigationDestination(for: MastodonStatus.self) { status in
                PostDetailView(status: status)
            }
        }
    }
}

// MARK: - TrendingTagRow

private struct TrendingTagRow: View {
    let tag: MastodonTag

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("#\(tag.name)")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Trending hashtag \(tag.name)")
    }
}

// MARK: - AccountSearchRow

private struct AccountSearchRow: View {
    let account: MastodonAccount

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: account.avatarURL, size: 44, shape: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName.isEmpty ? account.username : account.displayName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(account.acct)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(account.displayName), @\(account.acct)")
    }
}

// MARK: - HashtagFeedView

/// Minimal hashtag timeline stub — shows statuses tagged with a given hashtag.
struct HashtagFeedView: View {
    let hashtag: String

    @State private var statuses: [MastodonStatus] = []
    @State private var isLoading = false
    @State private var error: Error? = nil
    @State private var replyTarget: MastodonStatus? = nil
    @State private var client: MastodonAPIClient? = nil
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        Group {
            if isLoading && statuses.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if statuses.isEmpty {
                ContentUnavailableView(
                    "#\(hashtag)",
                    systemImage: "number",
                    description: Text(String(localized: "explore.hashtag.empty"))
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(statuses) { status in
                            NavigationLink(value: status) {
                                PostCardView(
                                    status: status,
                                    onTap: nil,
                                    onFavourite: { Task { await toggleFavourite(status) } },
                                    onBoost:     { Task { await boost(status) } },
                                    onReply:     { replyTarget = status }
                                )
                                .tint(.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationDestination(for: MastodonStatus.self) { status in
                    PostDetailView(status: status)
                }
            }
        }
        .navigationTitle("#\(hashtag)")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $replyTarget) { target in
            ComposeView(replyTo: target)
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            isLoading = true
            let c = MastodonAPIClient(
                instanceURL: credential.instanceURL,
                accessToken: credential.accessToken
            )
            client = c
            do {
                statuses = try await c.hashtagTimeline(hashtag: hashtag, limit: 40)
            } catch {
                self.error = error
            }
            isLoading = false
        }
    }

    private func toggleFavourite(_ status: MastodonStatus) async {
        guard let client else { return }
        applyUpdate(id: status.id) { s in
            s.isFavourited
                ? s.withFavouritesCount(s.favouritesCount - 1).withFavourited(false)
                : s.withFavouritesCount(s.favouritesCount + 1).withFavourited(true)
        }
        do {
            let updated = status.isFavourited
                ? try await client.unfavouriteStatus(id: status.id)
                : try await client.favouriteStatus(id: status.id)
            applyUpdate(id: updated.id) { _ in updated }
        } catch {
            self.error = error
            applyUpdate(id: status.id) { _ in status }
        }
    }

    private func boost(_ status: MastodonStatus) async {
        guard let client else { return }
        applyUpdate(id: status.id) { s in
            s.isReblogged
                ? s.withReblogsCount(s.reblogsCount - 1).withReblogged(false)
                : s.withReblogsCount(s.reblogsCount + 1).withReblogged(true)
        }
        do {
            let updated = status.isReblogged
                ? try await client.unboostStatus(id: status.id)
                : try await client.boostStatus(id: status.id)
            applyUpdate(id: updated.id) { _ in updated }
        } catch {
            self.error = error
            applyUpdate(id: status.id) { _ in status }
        }
    }

    private func applyUpdate(id: String, transform: (MastodonStatus) -> MastodonStatus) {
        guard let idx = statuses.firstIndex(where: { $0.id == id }) else { return }
        statuses[idx] = transform(statuses[idx])
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    ExploreView()
        .environment(AuthManager.shared)
}
#endif
