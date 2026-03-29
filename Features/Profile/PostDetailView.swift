// PostDetailView.swift
// Rosemount
//
// Full post-detail / thread view (Phase 2).
// Replaces PostDetailPlaceholderView from Phase 1.
//
// Shows the focal status's ancestors above it, the status itself highlighted,
// and its descendants below, all in one scrollable column.
// A pinned reply bar at the bottom lets the user compose a reply inline.
//
// Types referenced from other files:
//   MastodonAPIClient      — Core/Mastodon/MastodonAPIClient.swift
//   MastodonStatusContext  — Features/Messaging/MessageThreadView.swift
//   MastodonStatus         — Core/Mastodon/Models/MastodonStatus.swift
//   AccountCredential      — Core/Auth/AuthManager.swift
//   AuthManager            — Core/Auth/AuthManager.swift
//   PostCardView           — Shared/Components/PostCardView.swift
//   AvatarView             — Shared/Components/AvatarView.swift
//
// statusContext(id:) is defined in Features/Messaging/MessageThreadView.swift
// and returns MastodonStatusContext.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MARK: - PostDetailViewModel

@Observable
@MainActor
final class PostDetailViewModel {

    // MARK: - State

    var status: MastodonStatus
    var ancestors: [MastodonStatus] = []
    var descendants: [MastodonStatus] = []
    var isLoading: Bool = false
    var error: Error? = nil
    var replyDraft: String = ""

    // MARK: - Private

    private var client: MastodonAPIClient?

    // MARK: - Init

    init(status: MastodonStatus) {
        self.status = status
    }

    // MARK: - Setup

    /// Constructs the API client from the given credential.
    /// Must be called before `load()` or `submitReply()`.
    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Load Thread

    /// Fetches the thread context (ancestors + descendants) for `status`.
    ///
    /// Uses `statusContext(id:)` defined in Features/Messaging/MessageThreadView.swift,
    /// which returns `MastodonStatusContext`.
    func load() async {
        guard let client else { return }
        isLoading = true
        error = nil
        do {
            let context = try await client.statusContext(id: status.id)
            ancestors   = context.ancestors
            descendants = context.descendants
        } catch {
            self.error = error
        }
        isLoading = false
    }

    // MARK: - Submit Reply

    /// Posts a reply to `status` using `replyDraft`, then reloads the thread.
    func submitReply() async {
        guard let client else { return }
        let trimmed = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        do {
            _ = try await client.createStatus(
                content: trimmed,
                // Mirror the focal status's visibility, but cap at .public for replies.
                visibility: status.visibility == .direct ? .direct : .public,
                inReplyToId: status.id
            )
            replyDraft = ""
            await load()
        } catch {
            self.error = error
        }
    }
}

// MARK: - PostDetailView

/// Full-screen thread view for a single `MastodonStatus`.
struct PostDetailView: View {

    // MARK: - State

    @State private var viewModel: PostDetailViewModel
    @Environment(AuthManager.self) private var authManager

    // MARK: - Init

    init(status: MastodonStatus) {
        _viewModel = State(initialValue: PostDetailViewModel(status: status))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // ── Thread ──────────────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {

                        // Ancestors
                        ForEach(viewModel.ancestors) { ancestor in
                            PostCardView(status: ancestor)
                                .id("ancestor-\(ancestor.id)")
                        }

                        if !viewModel.ancestors.isEmpty {
                            Divider()
                        }

                        // Focal (highlighted) status
                        PostCardView(status: viewModel.status)
                            .id("focal")
                            // Slightly larger dynamic type to make the focal post
                            // visually prominent in the thread.
                            .environment(\.dynamicTypeSize, .large)
                            .background(Color(.secondarySystemBackground))

                        Divider()

                        // Descendants
                        ForEach(viewModel.descendants) { descendant in
                            PostCardView(status: descendant)
                                .id("descendant-\(descendant.id)")
                        }

                        // Loading spinner
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                                .id("spinner")
                        }

                        // Error banner
                        if let err = viewModel.error {
                            errorBanner(err)
                        }

                        // Padding so the last post clears the reply bar
                        Color.clear.frame(height: 16)
                    }
                }
                .onAppear {
                    // After the initial render, scroll to the focal post.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo("focal", anchor: .top)
                        }
                    }
                }
            }

            Divider()

            // ── Reply bar ─────────────────────────────────────────────
            replyBar
                .background(Color(.systemBackground))
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.load()
        }
    }

    // MARK: - Reply Bar

    private var replyBar: some View {
        HStack(spacing: 10) {
            // Own avatar (uses AccountCredential.avatarURL which is URL?)
            AvatarView(
                url: authManager.activeAccount?.avatarURL,
                size: 32,
                shape: .circle
            )

            // Draft field — grows up to 4 lines
            TextField("Reply…", text: $viewModel.replyDraft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

            // Send button — disabled when draft is empty
            let canSend = !viewModel.replyDraft
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            Button {
                Task { await viewModel.submitReply() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(canSend ? Color.accentColor : Color(.systemGray3))
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.red)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Retry") {
                Task { await viewModel.load() }
            }
            .font(.subheadline.weight(.medium))
        }
        .padding(12)
        .background(
            Color(.secondarySystemBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PostDetailView") {
    Text("PostDetailView requires a live MastodonStatus and AuthManager.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
}
#endif
