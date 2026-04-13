// ProfileViewModel.swift
// Rosemount
//
// ViewModel for viewing a user profile.

import SwiftUI
import Observation

// MARK: - MastodonAPIClient extension

extension MastodonAPIClient {
    /// GET /api/v1/accounts/:id/statuses
    func accountStatuses(
        id: String,
        maxId: String? = nil,
        limit: Int = 20
    ) async throws -> [MastodonStatus] {
        let base = instanceURL.appendingPathComponent("/api/v1/accounts/\(id)/statuses")
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else {
            throw MastodonClientError.invalidURL
        }
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let maxId {
            queryItems.append(URLQueryItem(name: "max_id", value: maxId))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw MastodonClientError.invalidURL }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder.mastodon.decode([MastodonStatus].self, from: data)
    }
}

// MARK: - ProfileViewModel

@Observable
@MainActor
final class ProfileViewModel {

    // MARK: State

    var account: MastodonAccount?
    var statuses: [MastodonStatus] = []
    var relationship: MastodonRelationship?
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: Error?
    var hasMore: Bool = true

    // MARK: Private

    private var oldestId: String?
    private var client: MastodonAPIClient?
    private var activeAccount: AccountCredential?
    private var currentAccountId: String?

    // MARK: Setup

    func setup(with credential: AccountCredential) {
        activeAccount = credential
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: Computed

    var isOwnProfile: Bool {
        guard let activeAccount, let account else { return false }
        return account.id == activeAccount.id
    }

    var followButtonTitle: String {
        guard let relationship else { return "Follow" }
        if relationship.requested { return "Requested" }
        if relationship.following { return "Unfollow" }
        return "Follow"
    }

    // MARK: Load

    func load(accountId: String) async {
        guard let client else { return }
        currentAccountId = accountId
        isLoading = true
        error = nil

        do {
            async let fetchedAccount = client.account(id: accountId)
            async let fetchedStatuses = client.accountStatuses(id: accountId, maxId: nil, limit: 20)
            async let fetchedRelationships = client.relationships(ids: [accountId])

            let (acct, fetched, relationships) = try await (
                fetchedAccount,
                fetchedStatuses,
                fetchedRelationships
            )

            account = acct
            statuses = fetched
            oldestId = fetched.last?.id
            hasMore = fetched.count == 20
            relationship = relationships.first
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: Pagination

    func loadMore() async {
        guard let client,
              let accountId = currentAccountId,
              !isLoadingMore,
              hasMore else { return }

        isLoadingMore = true

        do {
            let more = try await client.accountStatuses(
                id: accountId,
                maxId: oldestId,
                limit: 20
            )
            statuses.append(contentsOf: more)
            oldestId = more.last?.id
            hasMore = more.count == 20
        } catch {
            self.error = error
        }

        isLoadingMore = false
    }

    // MARK: Social Actions

    func toggleFollow() async {
        guard let client, let account else { return }

        // Optimistic update
        let wasFollowing = relationship?.following ?? false
        let wasRequested = relationship?.requested ?? false
        relationship = relationship.map { rel in
            MastodonRelationship(
                id: rel.id,
                following: wasFollowing ? false : (!account.locked),
                followedBy: rel.followedBy,
                blocking: rel.blocking,
                muting: rel.muting,
                requested: account.locked && !wasFollowing && !wasRequested
            )
        }

        do {
            let updated: MastodonRelationship
            if wasFollowing || wasRequested {
                updated = try await client.unfollow(id: account.id)
            } else {
                updated = try await client.follow(id: account.id)
            }
            relationship = updated
        } catch {
            // Revert optimistic update
            self.error = error
            let relationships = try? await client.relationships(ids: [account.id])
            relationship = relationships?.first
        }
    }

    func block() async {
        guard let client, let account else { return }
        do {
            relationship = try await client.block(id: account.id)
        } catch {
            self.error = error
        }
    }

    func mute() async {
        guard let client, let account else { return }
        do {
            relationship = try await client.mute(id: account.id)
        } catch {
            self.error = error
        }
    }
}
