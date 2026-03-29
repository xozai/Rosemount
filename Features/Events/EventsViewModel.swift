// Features/Events/EventsViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class EventsViewModel {
    var events: [RosemountEvent] = []
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var showUpcomingOnly: Bool = true
    var error: Error?
    var hasMore: Bool = true
    private var page: Int = 1
    private var client: EventAPIClient?
    private var communitySlug: String = ""

    func setup(communitySlug: String, credential: AccountCredential) {
        self.communitySlug = communitySlug
        client = EventAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        error = nil
        page = 1
        do {
            events = try await client.communityEvents(slug: communitySlug, upcoming: showUpcomingOnly, page: 1)
            hasMore = !events.isEmpty
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func loadMore() async {
        guard let client, hasMore, !isLoadingMore else { return }
        isLoadingMore = true
        do {
            let nextPage = page + 1
            let more = try await client.communityEvents(slug: communitySlug, upcoming: showUpcomingOnly, page: nextPage)
            if more.isEmpty {
                hasMore = false
            } else {
                events.append(contentsOf: more)
                page = nextPage
            }
        } catch {
            self.error = error
        }
        isLoadingMore = false
    }

    func rsvp(event: RosemountEvent, status: RSVPStatus) async {
        guard let client else { return }
        // Optimistic update
        if let idx = events.firstIndex(where: { $0.id == event.id }) {
            // We can't mutate struct fields via index directly — replace
            // RosemountEvent is immutable; reload after success
        }
        do {
            let updated = try await client.rsvp(eventId: event.id, status: status)
            if let idx = events.firstIndex(where: { $0.id == updated.id }) {
                events[idx] = updated
            }
        } catch {
            self.error = error
        }
    }
}
