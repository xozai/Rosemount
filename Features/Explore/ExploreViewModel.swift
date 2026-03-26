// ExploreViewModel.swift
// Rosemount
//
// ViewModel for the Explore / Hashtag / Trending screen.
// Uses @Observable (Swift 5.10 / iOS 17) and async/await.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// MastodonAPIClient      — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonSearchResults  — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonTag            — defined in Core/Mastodon/Models/MastodonStatus.swift
// AccountCredential      — defined in Core/Auth/AuthManager.swift

// MARK: - ExploreViewModel

@Observable
@MainActor
final class ExploreViewModel {

    // MARK: - Published State

    /// The current search query string (two-way bound via .searchable).
    var searchQuery: String = ""

    /// Results returned by the last search request.
    var searchResults: MastodonSearchResults? = nil

    /// Trending hashtags shown when `searchQuery` is empty.
    var trendingTags: [MastodonTag] = []

    /// `true` while a network request is in flight.
    var isLoading: Bool = false

    /// `true` while the trending section is loading on first appear.
    var isTrendingLoading: Bool = false

    /// Non-`nil` when a network error has occurred.
    var error: Error? = nil

    // MARK: - Private State

    private var client: MastodonAPIClient? = nil

    /// Tracks the query that produced the current `searchResults` to avoid duplicates.
    private var lastSearchedQuery: String = ""

    /// Debounce task — cancelled and replaced on each keystroke.
    private var debounceTask: Task<Void, Never>? = nil

    // MARK: - Setup

    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Trending Tags

    /// Loads trending hashtags shown when the search field is empty.
    func loadTrendingTags() async {
        guard let client, trendingTags.isEmpty else { return }

        isTrendingLoading = true
        error = nil

        do {
            trendingTags = try await client.trendingTags(limit: 20)
        } catch {
            // Trending is non-critical; show empty state rather than blocking.
            self.error = error
        }

        isTrendingLoading = false
    }

    // MARK: - Search (debounced)

    /// Called whenever `searchQuery` changes.
    /// Cancels any pending debounce and starts a new 350 ms timer.
    func onQueryChanged(_ query: String) {
        debounceTask?.cancel()

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            searchResults = nil
            lastSearchedQuery = ""
            isLoading = false
            return
        }

        debounceTask = Task {
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmed)
        }
    }

    /// Executes the search immediately (used by debounce timer and on submit).
    func performSearch(query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != lastSearchedQuery else { return }
        guard let client else { return }

        isLoading = true
        error = nil

        do {
            let results = try await client.search(query: trimmed, limit: 20)
            lastSearchedQuery = trimmed
            searchResults = results
        } catch {
            self.error = error
        }

        isLoading = false
    }
}
