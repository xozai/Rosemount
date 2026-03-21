// FollowersView.swift
// Rosemount
//
// Followers and following lists.

import SwiftUI
import Observation

// MARK: - FollowListType

enum FollowListType {
    case followers
    case following

    var title: String {
        switch self {
        case .followers: return "Followers"
        case .following: return "Following"
        }
    }
}

// MARK: - MastodonAPIClient extensions

extension MastodonAPIClient {
    /// GET /api/v1/accounts/:id/followers
    func followers(
        id: String,
        maxId: String? = nil,
        limit: Int = 40
    ) async throws -> [MastodonAccount] {
        try await fetchAccountList(
            path: "/api/v1/accounts/\(id)/followers",
            maxId: maxId,
            limit: limit
        )
    }

    /// GET /api/v1/accounts/:id/following
    func following(
        id: String,
        maxId: String? = nil,
        limit: Int = 40
    ) async throws -> [MastodonAccount] {
        try await fetchAccountList(
            path: "/api/v1/accounts/\(id)/following",
            maxId: maxId,
            limit: limit
        )
    }

    // MARK: Private Helper

    private func fetchAccountList(
        path: String,
        maxId: String?,
        limit: Int
    ) async throws -> [MastodonAccount] {
        var components = URLComponents(
            url: instanceURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let maxId {
            queryItems.append(URLQueryItem(name: "max_id", value: maxId))
        }
        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder.mastodon.decode([MastodonAccount].self, from: data)
    }
}

// MARK: - FollowListViewModel

@Observable
@MainActor
final class FollowListViewModel {

    var accounts: [MastodonAccount] = []
    var relationships: [String: MastodonRelationship] = [:]
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var hasMore: Bool = true
    var error: Error?

    private var client: MastodonAPIClient?
    private var activeAccount: AccountCredential?
    private var currentAccountId: String?
    private var currentType: FollowListType?
    private var oldestId: String?

    func setup(with credential: AccountCredential) {
        activeAccount = credential
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    var activeAccountId: String? { activeAccount?.id }

    func load(accountId: String, type: FollowListType) async {
        guard let client else { return }
        currentAccountId = accountId
        currentType = type
        isLoading = true
        error = nil
        oldestId = nil

        do {
            let fetched: [MastodonAccount]
            switch type {
            case .followers:
                fetched = try await client.followers(id: accountId, maxId: nil, limit: 40)
            case .following:
                fetched = try await client.following(id: accountId, maxId: nil, limit: 40)
            }
            accounts = fetched
            oldestId = fetched.last?.id
            hasMore = fetched.count == 40
            await fetchRelationships(for: fetched.map(\.id))
        } catch {
            self.error = error
        }

        isLoading = false
    }

    func loadMore() async {
        guard let client,
              let accountId = currentAccountId,
              let type = currentType,
              !isLoadingMore,
              hasMore else { return }

        isLoadingMore = true

        do {
            let more: [MastodonAccount]
            switch type {
            case .followers:
                more = try await client.followers(id: accountId, maxId: oldestId, limit: 40)
            case .following:
                more = try await client.following(id: accountId, maxId: oldestId, limit: 40)
            }
            accounts.append(contentsOf: more)
            oldestId = more.last?.id
            hasMore = more.count == 40
            await fetchRelationships(for: more.map(\.id))
        } catch {
            self.error = error
        }

        isLoadingMore = false
    }

    func toggleFollow(for account: MastodonAccount) async {
        guard let client else { return }
        let rel = relationships[account.id]
        let wasFollowing = rel?.following ?? false
        let wasRequested = rel?.requested ?? false

        do {
            let updated: MastodonRelationship
            if wasFollowing || wasRequested {
                updated = try await client.unfollow(id: account.id)
            } else {
                updated = try await client.follow(id: account.id)
            }
            relationships[account.id] = updated
        } catch {
            self.error = error
        }
    }

    // MARK: Private

    private func fetchRelationships(for ids: [String]) async {
        guard let client, !ids.isEmpty else { return }
        let filtered = ids.filter { $0 != activeAccount?.id }
        guard !filtered.isEmpty else { return }

        if let rels = try? await client.relationships(ids: filtered) {
            for rel in rels {
                relationships[rel.id] = rel
            }
        }
    }
}

// MARK: - FollowersView

struct FollowersView: View {
    let accountId: String
    let type: FollowListType

    @State private var viewModel = FollowListViewModel()
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        List {
            ForEach(viewModel.accounts) { account in
                AccountRowView(
                    account: account,
                    relationship: viewModel.relationships[account.id],
                    isOwnProfile: account.id == viewModel.activeAccountId,
                    onFollowTap: {
                        Task { await viewModel.toggleFollow(for: account) }
                    }
                )
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .onAppear {
                    if account.id == viewModel.accounts.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .navigationTitle(type.title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if viewModel.isLoading && viewModel.accounts.isEmpty {
                ProgressView()
            } else if !viewModel.isLoading && viewModel.accounts.isEmpty {
                ContentUnavailableView(
                    type == .followers ? "No Followers Yet" : "Not Following Anyone",
                    systemImage: "person.2",
                    description: Text(
                        type == .followers
                            ? "Followers will appear here."
                            : "Followed accounts will appear here."
                    )
                )
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.load(accountId: accountId, type: type)
        }
        .refreshable {
            await viewModel.load(accountId: accountId, type: type)
        }
    }
}

// MARK: - AccountRowView

private struct AccountRowView: View {
    let account: MastodonAccount
    let relationship: MastodonRelationship?
    let isOwnProfile: Bool
    let onFollowTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: account.id) {
                HStack(spacing: 12) {
                    AvatarView(
                        url: URL(string: account.avatarURL ?? ""),
                        size: 44,
                        shape: .circle
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(account.displayName.isEmpty ? account.username : account.displayName)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)

                            if account.bot {
                                Image(systemName: "cpu")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if account.locked {
                                Image(systemName: "lock.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text("@\(account.acct)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            FollowButton(
                relationship: relationship,
                isOwnProfile: isOwnProfile,
                onTap: onFollowTap
            )
        }
    }
}

// MARK: - FollowButton

struct FollowButton: View {
    let relationship: MastodonRelationship?
    let isOwnProfile: Bool
    let onTap: () -> Void

    @State private var isAnimating = false

    private var style: ButtonStyle {
        guard !isOwnProfile else { return .hidden }
        guard let rel = relationship else { return .follow }
        if rel.requested { return .requested }
        if rel.following { return .following }
        return .follow
    }

    var body: some View {
        if style != .hidden {
            Button {
                isAnimating = true
                onTap()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isAnimating = false
                }
            } label: {
                Text(style.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(style.foregroundColor)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(style.backgroundColor)
                    .overlay {
                        if style.hasBorder {
                            Capsule()
                                .strokeBorder(style.borderColor, lineWidth: 1)
                        }
                    }
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(isAnimating)
            .scaleEffect(isAnimating ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isAnimating)
        }
    }

    // MARK: Button Style

    private enum ButtonStyle: Equatable {
        case follow
        case following
        case requested
        case hidden

        var title: String {
            switch self {
            case .follow:     return "Follow"
            case .following:  return "Following"
            case .requested:  return "Requested"
            case .hidden:     return ""
            }
        }

        var foregroundColor: Color {
            switch self {
            case .follow:     return .white
            case .following:  return .primary
            case .requested:  return .secondary
            case .hidden:     return .clear
            }
        }

        var backgroundColor: Color {
            switch self {
            case .follow:     return .blue
            case .following:  return .clear
            case .requested:  return .clear
            case .hidden:     return .clear
            }
        }

        var hasBorder: Bool {
            switch self {
            case .follow:    return false
            case .following: return true
            case .requested: return true
            case .hidden:    return false
            }
        }

        var borderColor: Color {
            switch self {
            case .following: return .secondary.opacity(0.5)
            case .requested: return .secondary.opacity(0.3)
            default:         return .clear
            }
        }
    }
}

#Preview {
    NavigationStack {
        FollowersView(accountId: "1", type: .followers)
            .environment(AuthManager.shared)
    }
}
