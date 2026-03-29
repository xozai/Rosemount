// Core/Scheduled/ScheduledPostService.swift
// Scheduled post management via local notifications + background delivery

import BackgroundTasks
import Foundation
import SwiftData
import UserNotifications

// MARK: - Scheduled Post Model

@Model
final class ScheduledPost {
    var id: UUID
    var content: String
    var visibility: String
    var scheduledFor: Date
    var communitySlug: String?
    var mediaURLs: [String]
    var status: String      // "pending", "posted", "failed"
    var errorMessage: String?
    var createdAt: Date
    var notificationId: String

    init(content: String, visibility: String, scheduledFor: Date, communitySlug: String? = nil, mediaURLs: [String] = []) {
        self.id = UUID()
        self.content = content
        self.visibility = visibility
        self.scheduledFor = scheduledFor
        self.communitySlug = communitySlug
        self.mediaURLs = mediaURLs
        self.status = "pending"
        self.createdAt = Date()
        self.notificationId = UUID().uuidString
    }

    var isPending: Bool { status == "pending" }
    var isPosted: Bool { status == "posted" }
}

// MARK: - Scheduled Post Service

@Observable
@MainActor
final class ScheduledPostService {
    static let shared = ScheduledPostService()
    private let taskId = "com.rosemount.scheduled.post"
    var scheduledPosts: [ScheduledPost] = []
    private var container: ModelContainer?

    private init() {
        do {
            let schema = Schema([ScheduledPost.self])
            container = try ModelContainer(for: schema)
            scheduledPosts = fetchAll()
        } catch {
            // non-fatal
        }
    }

    private var context: ModelContext? { container?.mainContext }

    // MARK: CRUD

    func schedule(
        content: String,
        visibility: MastodonVisibility,
        scheduledFor: Date,
        communitySlug: String? = nil
    ) async throws {
        let post = ScheduledPost(
            content: content,
            visibility: visibility.rawValue,
            scheduledFor: scheduledFor,
            communitySlug: communitySlug
        )
        context?.insert(post)
        try? context?.save()
        scheduledPosts = fetchAll()
        await scheduleLocalNotification(for: post)
    }

    func cancelScheduled(_ post: ScheduledPost) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [post.notificationId])
        context?.delete(post)
        try? context?.save()
        scheduledPosts = fetchAll()
    }

    func fetchAll() -> [ScheduledPost] {
        let desc = FetchDescriptor<ScheduledPost>(sortBy: [SortDescriptor(\.scheduledFor)])
        return (try? context?.fetch(desc)) ?? []
    }

    // MARK: Delivery

    func deliverDuePosts(credential: AccountCredential) async {
        let now = Date()
        let due = scheduledPosts.filter { $0.isPending && $0.scheduledFor <= now }
        let client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
        for post in due {
            do {
                _ = try await client.createStatus(
                    content: post.content,
                    visibility: MastodonVisibility(rawValue: post.visibility) ?? .public
                )
                post.status = "posted"
            } catch {
                post.status = "failed"
                post.errorMessage = error.localizedDescription
            }
        }
        try? context?.save()
        scheduledPosts = fetchAll()
    }

    // MARK: Local Notification

    private func scheduleLocalNotification(for post: ScheduledPost) async {
        let center = UNUserNotificationCenter.current()
        _ = try? await center.requestAuthorization(options: [.alert, .sound])

        let content = UNMutableNotificationContent()
        content.title = "Scheduled Post"
        content.body = String(post.content.prefix(80))
        content.sound = .default
        content.userInfo = ["scheduled_post_id": post.id.uuidString]

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: post.scheduledFor)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: post.notificationId, content: content, trigger: trigger)
        try? await center.add(request)
    }
}
