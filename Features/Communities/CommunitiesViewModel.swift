// CommunitiesViewModel.swift
// Rosemount
//
// ViewModel for the Communities tab. Manages joined communities, discovery,
// search, join, and leave operations.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation

// RosemountCommunity  — defined in Core/Communities/Models/RosemountCommunity.swift
// CommunityAPIClient  — defined in Core/Communities/CommunityAPIClient.swift
// AccountCredential   — defined in Core/Auth/AuthManager.swift

// MARK: - CommunityTab

/// Selects between the user's joined communities and the discovery feed.
enum CommunityTab: Int, CaseIterable, Identifiable {
    case joined
    case discover

    var id: Int { rawValue }

    /// Human-readable label shown in the segmented picker.
    var title: String {
        switch self {
        case .joined:   return "Joined"
        case .discover: return "Discover"
        }
    }
}

// MARK: - CommunitiesViewModel

@Observable
@MainActor
final class CommunitiesViewModel {

    // MARK: - Published State

    /// Communities the authenticated user has already joined.
    var joinedCommunities: [RosemountCommunity] = []

    /// Communities surfaced by the discovery / search feed.
    var discoveredCommunities: [RosemountCommunity] = []

    /// Current value of the search field; updating it triggers a debounced search.
    var searchQuery: String = ""

    /// `true` while the initial or pull-to-refresh load is in flight.
    var isLoading: Bool = false

    /// `true` while a search request is in flight.
    var isSearching: Bool = false

    /// Non-`nil` when an error occurred during the most recent network operation.
    var error: Error? = nil

    /// Controls which segment is active in the picker.
    var selectedTab: CommunityTab = .joined

    // MARK: - Private State

    private var client: CommunityAPIClient?

    /// Task handle for the debounce timer so it can be cancelled on each new keystroke.
    private var searchTask: Task<Void, Never>?

    // MARK: - Setup

    /// Configures the view-model for a specific authenticated account.
    /// Must be called before `refresh()` or `search()`.
    ///
    /// - Parameter credential: The active `AccountCredential`.
    func setup(with credential: AccountCredential) {
        client = CommunityAPIClient(credential: credential)
        // Reset state on account change.
        joinedCommunities = []
        discoveredCommunities = []
        searchQuery = ""
        error = nil
    }

    // MARK: - Refresh

    /// Clears and reloads both joined communities and the first page of discovery results
    /// concurrently using `async let`.
    func refresh() async {
        guard let client else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil

        do {
            async let joined    = client.myCommunities()
            async let discover  = client.discoverCommunities(search: nil, page: 1)

            let (joinedResult, discoverResult) = try await (joined, discover)
            joinedCommunities    = joinedResult
            discoveredCommunities = discoverResult
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Search

    /// Performs a debounced search against the discovery endpoint.
    ///
    /// Waits 350 ms after the last call before firing the network request,
    /// cancelling any pending search when a new one arrives.
    func search() async {
        // Cancel any in-flight debounce task.
        searchTask?.cancel()

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        // If the query is empty, revert to the default discover list.
        if query.isEmpty {
            await loadDiscoverPage()
            return
        }

        searchTask = Task {
            // 350 ms debounce delay.
            do {
                try await Task.sleep(for: .milliseconds(350))
            } catch {
                // Task was cancelled — bail out silently.
                return
            }

            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }

        await searchTask?.value
    }

    // MARK: - Join / Leave

    /// Optimistically marks a community as joined, fires the API call, then rolls back on failure.
    ///
    /// - Parameter community: The community to join.
    func join(_ community: RosemountCommunity) async {
        guard let client else { return }

        // Optimistic update in the discover list.
        applyOptimisticMembership(communityId: community.id, isMember: true,
                                  role: .member, in: \.discoveredCommunities)

        do {
            let updated = try await client.joinCommunity(slug: community.slug)
            replace(updated, in: \.discoveredCommunities)
            // Prepend to joined list if not already present.
            if !joinedCommunities.contains(where: { $0.id == updated.id }) {
                joinedCommunities.insert(updated, at: 0)
            }
        } catch {
            // Roll back optimistic update.
            applyOptimisticMembership(communityId: community.id, isMember: false,
                                      role: nil, in: \.discoveredCommunities)
            self.error = error
        }
    }

    /// Removes the authenticated user from a community.
    ///
    /// - Parameter community: The community to leave.
    func leave(_ community: RosemountCommunity) async {
        guard let client else { return }

        // Optimistic removal from joined list.
        let previousJoined = joinedCommunities
        joinedCommunities.removeAll { $0.id == community.id }
        applyOptimisticMembership(communityId: community.id, isMember: false,
                                  role: nil, in: \.discoveredCommunities)

        do {
            try await client.leaveCommunity(slug: community.slug)
        } catch {
            // Roll back.
            joinedCommunities = previousJoined
            applyOptimisticMembership(communityId: community.id, isMember: true,
                                      role: community.myRole, in: \.discoveredCommunities)
            self.error = error
        }
    }

    // MARK: - Private Helpers

    /// Reloads the default (unfiltered) discovery page.
    private func loadDiscoverPage() async {
        guard let client else { return }

        isSearching = true
        error = nil

        do {
            discoveredCommunities = try await client.discoverCommunities(search: nil, page: 1)
        } catch {
            self.error = error
        }

        isSearching = false
    }

    /// Sends a search request and updates `discoveredCommunities` with results.
    private func performSearch(query: String) async {
        guard let client else { return }

        isSearching = true
        error = nil

        do {
            discoveredCommunities = try await client.discoverCommunities(search: query, page: 1)
        } catch {
            if !(error is CancellationError) {
                self.error = error
            }
        }

        isSearching = false
    }

    /// Writes an optimistic isMember / myRole patch to the community with the given ID.
    private func applyOptimisticMembership(
        communityId: String,
        isMember: Bool,
        role: CommunityRole?,
        in keyPath: ReferenceWritableKeyPath<CommunitiesViewModel, [RosemountCommunity]>
    ) {
        guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == communityId }) else { return }
        self[keyPath: keyPath][index] = self[keyPath: keyPath][index].withMembership(isMember: isMember, role: role)
    }

    /// Replaces an existing community in the target array by ID.
    private func replace(
        _ updated: RosemountCommunity,
        in keyPath: ReferenceWritableKeyPath<CommunitiesViewModel, [RosemountCommunity]>
    ) {
        guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == updated.id }) else { return }
        self[keyPath: keyPath][index] = updated
    }
}

// NOTE: RosemountCommunity.withMembership(isMember:role:) is defined in
// CommunityDetailViewModel.swift as an internal extension and is visible
// across the module — no duplicate definition needed here.
