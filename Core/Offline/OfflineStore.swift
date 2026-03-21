// Core/Offline/OfflineStore.swift
// SwiftData container and offline cache management

import Foundation
import SwiftData

@Observable
@MainActor
final class OfflineStore {
    static let shared = OfflineStore()
    private(set) var container: ModelContainer?
    var isOffline: Bool = false

    private init() {
        do {
            let schema = Schema([DraftPost.self, CachedStatus.self, PendingAction.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            // Fall back to in-memory
            let schema = Schema([DraftPost.self, CachedStatus.self, PendingAction.self])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try? ModelContainer(for: schema, configurations: config)
        }
    }

    var context: ModelContext? { container?.mainContext }

    // MARK: Drafts

    func saveDraft(_ draft: DraftPost) {
        context?.insert(draft)
        try? context?.save()
    }

    func deleteDraft(_ draft: DraftPost) {
        context?.delete(draft)
        try? context?.save()
    }

    func allDrafts() -> [DraftPost] {
        let desc = FetchDescriptor<DraftPost>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context?.fetch(desc)) ?? []
    }

    // MARK: Timeline Cache

    func cacheStatuses(_ statuses: [MastodonStatus], timelineType: String) {
        guard let ctx = context else { return }
        // Clear old cache for this timeline
        let pred = #Predicate<CachedStatus> { $0.timelineType == timelineType }
        try? ctx.delete(model: CachedStatus.self, where: pred)
        // Insert new
        for (i, status) in statuses.prefix(100).enumerated() {
            ctx.insert(CachedStatus(from: status, timelineType: timelineType, sortOrder: i))
        }
        try? ctx.save()
    }

    func cachedStatuses(timelineType: String) -> [CachedStatus] {
        let pred = #Predicate<CachedStatus> { $0.timelineType == timelineType }
        let desc = FetchDescriptor<CachedStatus>(predicate: pred, sortBy: [SortDescriptor(\.sortOrder)])
        return (try? context?.fetch(desc)) ?? []
    }

    // MARK: Pending Actions

    func enqueuePendingAction(type: String, targetId: String, payload: String? = nil) {
        let action = PendingAction(type: type, targetId: targetId, payload: payload)
        context?.insert(action)
        try? context?.save()
    }

    func allPendingActions() -> [PendingAction] {
        let desc = FetchDescriptor<PendingAction>(sortBy: [SortDescriptor(\.createdAt)])
        return (try? context?.fetch(desc)) ?? []
    }

    func removePendingAction(_ action: PendingAction) {
        context?.delete(action)
        try? context?.save()
    }
}
