// PostDetailView.swift
// Rosemount
//
// Full post-detail / thread view.  Replaces the PostDetailPlaceholderView stub
// that shipped in Phase 1.
//
// Shows ancestors above the focal post, the post itself highlighted in the
// centre, descendants below, and a reply bar pinned at the bottom of the screen.
//
// Types referenced from other files:
//   MastodonAPIClient   — Core/Mastodon/MastodonAPIClient.swift  (statusContext, createStatus)
//   MastodonStatus      — Core/Mastodon/Models/MastodonStatus.swift
//   AccountCredential   — Core/Auth/AuthManager.swift
//   AuthManager         — Core/Auth/AuthManager.swift
//   PostCardView        — Shared/Components/PostCardView.swift
//   AvatarView          — Shared/Components/AvatarView.swift
//   stripHTML           — Shared/Components/PostCardView.swift
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
    private var credential: AccountCredential?

    // MARK: - Init

    init(status: MastodonStatus) {
        self.status = status
    }

    // MARK: - Setup

    /// Stores the active credential and constructs the API client.
    func setup(with credential: AccountCredential) {
        self.credential = credential
        self.client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Load

    /// Fetches the thread context (ancestors + descendants) for `status`.
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

    // MARK: - Reply

    /// Posts a reply to `status` using the current `replyDraft` text, then reloads.
    func submitReply() async {
        guard let client else { return }
        let content = replyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }

        do {
            _ = try await client.createStatus(
                content: content,
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

/// Full thread view for a single `MastodonStatus`.
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
            // ── Thread scroll area ────────────────────────────────────────
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {

                        // Ancestors
                        ForEach(viewModel.ancestors) { ancestor in
                            PostCardView(status: ancestor)
                                .id(ancestor.id)
                        }

                        // Focal status separator
                        if !viewModel.ancestors.isEmpty {
                            Divider()
                        }

                        // Focal (highlighted) status
                        focalStatusCard
                            .id("focal")

                        Divider()

                        // Descendants
                        ForEach(viewModel.descendants) { descendant in
                            PostCardView(status: descendant)
                                .id(descendant.id)
                        }

                        // Loading indicator for thread fetch
                        if viewModel.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 24)
                        }

                        // Error banner
                        if let error = viewModel.error {
                            errorBanner(error)
                        }

                        // Bottom spacer so reply bar doesn't obscure last post
                        Color.clear.frame(height: 20)
                    }
                }
                .onAppear {
                    // Scroll to the focal post after the view loads.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation {
                            proxy.scrollTo("focal", anchor: .top)
                        }
                    }
                }
            }

            Divider()

            // ── Reply bar ─────────────────────────────────────────────────
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

    // MARK: - Focal Status Card

    /// The central, highlighted version of the focal status — slightly larger than
    /// surrounding thread entries and without a tap-to-navigate gesture.
    private var focalStatusCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostCardView(status: viewModel.status)
                // Override default font sizes via environment modifiers so
                // the focal post reads slightly larger.
                .environment(\.dynamicTypeSize, .large)
        }
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Reply Bar

    private var replyBar: some View {
        HStack(spacing: 10) {
            // Own avatar
            AvatarView(
                url: authManager.activeAccount?.avatarURL,
                size: 32,
                shape: .circle
            )

            // Draft text field
            TextField("Reply…", text: $viewModel.replyDraft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

            // Send button — disabled while draft is empty
            Button {
                Task { await viewModel.submitReply() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(
                        viewModel.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? Color(.systemGray3)
                            : Color.accentColor
                    )
            }
            .disabled(
                viewModel.replyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
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
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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
