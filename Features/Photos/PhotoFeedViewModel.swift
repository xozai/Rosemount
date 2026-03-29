// Features/Photos/PhotoFeedViewModel.swift
// View model for the Pixelfed-style photo feed tab.

import Foundation
import Observation

enum PhotoFeedType: String, CaseIterable {
    case home     = "Home"
    case discover = "Discover"
}

@Observable
@MainActor
final class PhotoFeedViewModel {
    var posts: [MastodonStatus] = []
    var feedType: PhotoFeedType = .home
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: Error?
    var isPixelfedAccount: Bool = false

    private var hasMore: Bool = true
    private var client: PixelfedAPIClient?
    private var credential: AccountCredential?

    func setup(with credential: AccountCredential) {
        self.credential = credential
        isPixelfedAccount = credential.platform == .pixelfed
        client = PixelfedAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        error = nil
        hasMore = true
        do {
            posts = try await fetchPage(maxId: nil)
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func switchFeed(to type: PhotoFeedType) async {
        feedType = type
        await refresh()
    }

    func loadMore() async {
        guard let client, !isLoadingMore, hasMore, let lastId = posts.last?.id else { return }
        isLoadingMore = true
        do {
            let more = try await fetchPage(maxId: lastId)
            if more.isEmpty { hasMore = false }
            posts.append(contentsOf: more)
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }

    private func fetchPage(maxId: String?) async throws -> [MastodonStatus] {
        guard let client else { return [] }
        switch feedType {
        case .home:
            return try await client.timeline(maxId: maxId, limit: 30)
                .filter { !$0.mediaAttachments.isEmpty }
        case .discover:
            return try await client.discoverFeed(maxId: maxId, limit: 30)
        }
    }
}
