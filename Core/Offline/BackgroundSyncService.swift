// Core/Offline/BackgroundSyncService.swift
// BGAppRefreshTask and BGProcessingTask for background sync

import BackgroundTasks
import Foundation
import Network
import Observation

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
    }

    // MARK: Scheduling

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleProcessingSync() {
        let request = BGProcessingTaskRequest(identifier: Self.syncTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        try? BGTaskScheduler.shared.submit(request)
    }

    // MARK: Handlers

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh() // Re-schedule for next time

        let syncTask = Task {
            await syncPendingActions()
        }

        task.expirationHandler = { syncTask.cancel() }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    private func handleProcessingTask(task: BGProcessingTask) {
        let syncTask = Task {
            await syncPendingActions()
            await refreshTimelineCache()
        }

        task.expirationHandler = { syncTask.cancel() }

        Task {
            await syncTask.value
            task.setTaskCompleted(success: true)
        }
    }

    // MARK: Sync Logic

    @MainActor
    func syncPendingActions() async {
        guard NetworkMonitor.shared.isConnected else { return }
        guard let credential = AuthManager.shared.activeAccount else { return }

        let store = OfflineStore.shared
        let pending = store.allPendingActions()
        let client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)

        for action in pending {
            do {
                switch action.type {
                case "favourite":
                    _ = try await client.favouriteStatus(id: action.targetId)
                    store.removePendingAction(action)
                case "boost":
                    _ = try await client.boostStatus(id: action.targetId)
                    store.removePendingAction(action)
                case "follow":
                    _ = try await client.followAccount(id: action.targetId)
                    store.removePendingAction(action)
                default:
                    store.removePendingAction(action) // Unknown action — discard
                }
            } catch {
                // Increment retry count; remove if too many failures
                if action.retryCount >= 3 { store.removePendingAction(action) }
            }
        }
    }

    @MainActor
    func refreshTimelineCache() async {
        guard NetworkMonitor.shared.isConnected else { return }
        guard let credential = AuthManager.shared.activeAccount else { return }

        let client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
        let store = OfflineStore.shared
        if let statuses = try? await client.homeTimeline(maxId: nil, sinceId: nil, limit: 40) {
            store.cacheStatuses(statuses, timelineType: "home")
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
    func delete(_ draft: DraftPost) { store.deleteDraft(draft); load() }
    func save(content: String, visibility: MastodonVisibility, communitySlug: String?) {
        let draft = DraftPost(content: content, visibility: visibility.rawValue, communitySlug: communitySlug)
        store.saveDraft(draft)
        load()
    }
}
