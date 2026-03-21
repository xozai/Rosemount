// Features/Scheduled/ScheduledPostsView.swift
// View and manage scheduled posts

import SwiftUI

struct ScheduledPostsView: View {
    @State private var service = ScheduledPostService.shared
    @Environment(AuthManager.self) private var authManager
    @State private var showingCompose = false
    @State private var postToCancel: ScheduledPost? = nil

    var pendingPosts: [ScheduledPost] { service.scheduledPosts.filter { $0.isPending } }
    var pastPosts: [ScheduledPost] { service.scheduledPosts.filter { !$0.isPending } }

    var body: some View {
        NavigationStack {
            Group {
                if service.scheduledPosts.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 52))
                            .foregroundStyle(.secondary)
                        Text("No scheduled posts")
                            .foregroundStyle(.secondary)
                        Button("Schedule a Post") { showingCompose = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        if !pendingPosts.isEmpty {
                            Section("Upcoming") {
                                ForEach(pendingPosts, id: \.id) { post in
                                    ScheduledPostRow(post: post) {
                                        postToCancel = post
                                    }
                                }
                            }
                        }
                        if !pastPosts.isEmpty {
                            Section("Sent / Failed") {
                                ForEach(pastPosts, id: \.id) { post in
                                    ScheduledPostRow(post: post, onCancel: nil)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Scheduled Posts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCompose = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCompose) {
                SchedulePostComposeView()
                    .environment(authManager)
                    .onDisappear { service.scheduledPosts = service.fetchAll() }
            }
            .confirmationDialog("Cancel this scheduled post?", isPresented: .constant(postToCancel != nil), titleVisibility: .visible) {
                Button("Cancel Post", role: .destructive) {
                    if let p = postToCancel { service.cancelScheduled(p) }
                    postToCancel = nil
                }
                Button("Keep", role: .cancel) { postToCancel = nil }
            }
            .onAppear { service.scheduledPosts = service.fetchAll() }
        }
    }
}

struct ScheduledPostRow: View {
    let post: ScheduledPost
    let onCancel: (() -> Void)?

    private var dateText: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: post.scheduledFor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                statusBadge
                Spacer()
                Text(dateText).font(.caption).foregroundStyle(.secondary)
            }
            Text(post.content)
                .font(.body)
                .lineLimit(3)
            if let err = post.errorMessage {
                Text(err).font(.caption).foregroundStyle(.red)
            }
            if let cancel = onCancel {
                Button("Cancel Post", role: .destructive, action: cancel)
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color): (String, Color) = switch post.status {
        case "posted": ("Sent", .green)
        case "failed": ("Failed", .red)
        default: ("Scheduled", .orange)
        }
        Text(label)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct SchedulePostComposeView: View {
    @State private var content = ""
    @State private var scheduledFor = Date().addingTimeInterval(3600)
    @State private var visibility: MastodonVisibility = .public
    @State private var isScheduling = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Content") {
                    ZStack(alignment: .topLeading) {
                        if content.isEmpty { Text("What's on your mind?").foregroundStyle(.tertiary).padding(.top, 8) }
                        TextEditor(text: $content).frame(minHeight: 120)
                    }
                }
                Section("Settings") {
                    Picker("Visibility", selection: $visibility) {
                        ForEach(MastodonVisibility.allCases, id: \.self) { v in
                            Text(v.rawValue.capitalized).tag(v)
                        }
                    }
                    DatePicker("Scheduled for", selection: $scheduledFor, in: Date().addingTimeInterval(60)..., displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("Schedule Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") {
                        isScheduling = true
                        Task {
                            try? await ScheduledPostService.shared.schedule(
                                content: content, visibility: visibility, scheduledFor: scheduledFor
                            )
                            dismiss()
                        }
                    }
                    .disabled(content.trimmingCharacters(in: .whitespaces).isEmpty || isScheduling)
                }
            }
        }
    }
}
