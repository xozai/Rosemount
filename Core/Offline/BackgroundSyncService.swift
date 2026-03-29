// Core/Offline/BackgroundSyncService.swift
// BGAppRefreshTask and BGProcessingTask for background sync
//
// DraftPost / PendingAction — Core/Offline/DraftPost.swift
// OfflineStore              — Core/Offline/OfflineStore.swift
// MastodonAPIClient         — Core/Mastodon/MastodonAPIClient.swift

import BackgroundTasks
import Foundation
import Network
import OSLog
import Observation

private let logger = Logger(subsystem: "social.rosemount", category: "BackgroundSync")

// MARK: - Network Monitor

@Observable
@MainActor
final class NetworkMonitor {
    static let shared = NetworkMonitor()
    var isConnected: Bool = true
    var connectionType: NWInterface.InterfaceType?
    private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: DispatchQueue(label: "com.rosemount.network"))
    }

    var isWiFi: Bool { connectionType == .wifi }
    var isCellular: Bool { connectionType == .cellular }
}

// MARK: - Background Sync Service

final class BackgroundSyncService {
    static let shared = BackgroundSyncService()
    static let refreshTaskId = "com.rosemount.background.refresh"
    static let syncTaskId = "com.rosemount.background.sync"

    private init() {}

    // MARK: Registration (call from AppDelegate/App)

    static func registerTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshTaskId, using: nil) { task in
            Self.shared.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: syncTaskId, using: nil) { task in
            Self.shared.handleProcessingTask(task: task as! BGProcessingTask)
        }
        logger.info("Background tasks registered.")
    }

    // MARK: Scheduling

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("scheduleAppRefresh failed: \(error.localizedDescription)")
        }
    }

    func scheduleProcessingSync() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("scheduleProcessingSync failed: \(error.localizedDescription)")
        }
    }

    // MARK: Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let syncTask = Task {
            await syncPendingActions()
        }

        task.expirationHandler = {
            syncTask.cancel()
            logger.warning("BGAppRefreshTask expired before completion.")
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
            logger.info("BGAppRefreshTask completed.")
        }
    }

    private func handleProcessingTask(task: BGProcessingTask) {
        let syncTask = Task {
            await syncPendingActions()
            await refreshTimelineCache()
        }

        task.expirationHandler = {
            syncTask.cancel()
            logger.warning("BGProcessingTask expired before completion.")
        }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
            logger.info("BGProcessingTask completed.")
        }
    }

    // MARK: Sync Logic

    @MainActor
    func syncPendingActions() async {
        guard NetworkMonitor.shared.isConnected else {
            logger.debug("syncPendingActions skipped — offline.")
            return
        }
        guard let credential = AuthManager.shared.activeAccount else { return }

        let store = OfflineStore.shared
        let pending = store.allPendingActions()

        guard !pending.isEmpty else { return }
        logger.info("Syncing \(pending.count) pending action(s).")

        let client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)

        for action in pending {
            do {
                switch action.type {
                case "favourite":
                    _ = try await client.favouriteStatus(id: action.targetId)
                    store.removePendingAction(action)
                    logger.debug("Synced favourite for \(action.targetId)")
                case "boost":
                    _ = try await client.boostStatus(id: action.targetId)
                    store.removePendingAction(action)
                    logger.debug("Synced boost for \(action.targetId)")
                case "follow":
                    _ = try await client.followAccount(id: action.targetId)
                    store.removePendingAction(action)
                    logger.debug("Synced follow for \(action.targetId)")
                default:
                    logger.warning("Unknown pending action type '\(action.type)' — discarding.")
                    store.removePendingAction(action)
                }
            } catch {
                action.retryCount += 1
                if action.retryCount >= 3 {
                    logger.error("Pending action '\(action.type)' for \(action.targetId) failed after 3 attempts — discarding. Error: \(error.localizedDescription)")
                    store.removePendingAction(action)
                } else {
                    logger.warning("Pending action '\(action.type)' for \(action.targetId) failed (attempt \(action.retryCount)/3): \(error.localizedDescription)")
                }
            }
        }
    }

    @MainActor
    func refreshTimelineCache() async {
        guard NetworkMonitor.shared.isConnected else { return }
        guard let credential = AuthManager.shared.activeAccount else { return }

        let client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
        let store = OfflineStore.shared

        do {
            let statuses = try await client.homeTimeline(maxId: nil, sinceId: nil, limit: 40)
            store.cacheStatuses(statuses, timelineType: "home")
            logger.info("Timeline cache refreshed with \(statuses.count) statuses.")
        } catch {
            logger.error("refreshTimelineCache failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Drafts ViewModel

@Observable
@MainActor
final class DraftsViewModel {
    var drafts: [DraftPost] = []
    private let store = OfflineStore.shared

    func load() { drafts = store.allDrafts() }

    func delete(_ draft: DraftPost) {
        store.deleteDraft(draft)
        load()
    }

    func save(content: String, visibility: MastodonVisibility, communitySlug: String?) {
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let draft = DraftPost(content: content, visibility: visibility.rawValue, communitySlug: communitySlug)
        store.saveDraft(draft)
        load()
    }
}
