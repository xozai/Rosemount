// Core/Offline/OfflineStore.swift
// SwiftData container and offline cache management
//
// CachedStatus  — Shared/SwiftData/CachedStatus.swift
// DraftPost     — Core/Offline/DraftPost.swift
// PendingAction — Core/Offline/DraftPost.swift

import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "social.rosemount", category: "OfflineStore")

@Observable
@MainActor
final class OfflineStore {
    static let shared = OfflineStore()
    private(set) var container: ModelContainer?
    var isOffline: Bool = false

    private init() {
        let schema = Schema([DraftPost.self, CachedStatus.self, PendingAction.self])
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: config)
        } catch {
            logger.error("Persistent OfflineStore unavailable (\(error.localizedDescription)) — falling back to in-memory.")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try? ModelContainer(for: schema, configurations: config)
        }
    }

    var context: ModelContext? { container?.mainContext }

    // MARK: Drafts

    func saveDraft(_ draft: DraftPost) {
        guard let ctx = context else {
            logger.warning("saveDraft: no context available")
            return
        }
        draft.updatedAt = Date()
        ctx.insert(draft)
        do { try ctx.save() }
        catch { logger.error("saveDraft failed: \(error.localizedDescription)") }
    }

    func deleteDraft(_ draft: DraftPost) {
        guard let ctx = context else { return }
        ctx.delete(draft)
        do { try ctx.save() }
        catch { logger.error("deleteDraft failed: \(error.localizedDescription)") }
    }

    func allDrafts() -> [DraftPost] {
        let desc = FetchDescriptor<DraftPost>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        do { return try context?.fetch(desc) ?? [] }
        catch {
            logger.error("allDrafts fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Timeline Cache

    func cacheStatuses(_ statuses: [MastodonStatus], timelineType: String) {
        guard let ctx = context else { return }
        let pred = #Predicate<CachedStatus> { $0.timelineType == timelineType }
        do {
            try ctx.delete(model: CachedStatus.self, where: pred)
        } catch {
            logger.error("cacheStatuses delete failed: \(error.localizedDescription)")
        }
        for (i, status) in statuses.prefix(100).enumerated() {
            ctx.insert(CachedStatus(from: status, timelineType: timelineType, sortOrder: i))
        }
        do { try ctx.save() }
        catch { logger.error("cacheStatuses save failed: \(error.localizedDescription)") }
    }

    func cachedStatuses(timelineType: String) -> [CachedStatus] {
        let pred = #Predicate<CachedStatus> { $0.timelineType == timelineType }
        let desc = FetchDescriptor<CachedStatus>(predicate: pred, sortBy: [SortDescriptor(\.sortOrder)])
        do { return try context?.fetch(desc) ?? [] }
        catch {
            logger.error("cachedStatuses fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: Pending Actions

    func enqueuePendingAction(type: String, targetId: String, payload: String? = nil) {
        guard let ctx = context else {
            logger.warning("enqueuePendingAction: no context — action '\(type)' lost")
            return
        }
        let action = PendingAction(type: type, targetId: targetId, payload: payload)
        ctx.insert(action)
        do { try ctx.save() }
        catch { logger.error("enqueuePendingAction save failed: \(error.localizedDescription)") }
    }

    func allPendingActions() -> [PendingAction] {
        let desc = FetchDescriptor<PendingAction>(sortBy: [SortDescriptor(\.createdAt)])
        do { return try context?.fetch(desc) ?? [] }
        catch {
            logger.error("allPendingActions fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    func removePendingAction(_ action: PendingAction) {
        guard let ctx = context else { return }
        ctx.delete(action)
        do { try ctx.save() }
        catch { logger.error("removePendingAction save failed: \(error.localizedDescription)") }
    }

    /// Returns the count of unsynced pending actions.
    var pendingActionsCount: Int { allPendingActions().count }
}
