// Features/Events/GlobalEventsViewModel.swift
// View model for the global (non-community-scoped) Events tab.

import Foundation
import Observation

enum GlobalEventFilter: String, CaseIterable {
    case upcoming = "Upcoming"
    case past     = "Past"
    case mine     = "My Events"
}

@Observable
@MainActor
final class GlobalEventsViewModel {
    var events: [RosemountEvent] = []
    var filter: GlobalEventFilter = .upcoming
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: Error?
    private var hasMore: Bool = true
    private var client: EventAPIClient?

    func setup(with credential: AccountCredential) {
        client = EventAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        error = nil
        hasMore = true
        do {
            events = try await client.fetchEvents(
                upcoming: filter != .past,
                mine: filter == .mine
            )
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func switchFilter(to newFilter: GlobalEventFilter) async {
        filter = newFilter
        await refresh()
    }

    func loadMore() async {
        guard let client, !isLoadingMore, hasMore, let lastId = events.last?.id else { return }
        isLoadingMore = true
        do {
            let more = try await client.fetchEvents(
                upcoming: filter != .past,
                mine: filter == .mine,
                maxId: lastId
            )
            if more.isEmpty { hasMore = false }
            events.append(contentsOf: more)
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }

    func rsvp(_ event: RosemountEvent, status: RSVPStatus) async {
        guard let client else { return }
        do {
            let updated = try await client.rsvp(eventId: event.id, status: status)
            if let idx = events.firstIndex(where: { $0.id == event.id }) {
                events[idx] = updated
            }
        } catch {
            self.error = error
        }
    }
}
