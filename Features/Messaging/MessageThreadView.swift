// MessageThreadView.swift
// Rosemount
//
// Individual DM conversation thread view with chat-bubble layout and a
// bottom compose bar. Messages are Mastodon statuses with visibility=direct.
//
// NOTE: Phase 4 will add E2E encryption; this is a plaintext first pass.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonAPIClient    — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonStatus       — defined in Core/Mastodon/Models/MastodonStatus.swift
// MastodonConversation — defined in Core/Mastodon/Models/MastodonConversation.swift
// AccountCredential    — defined in Core/Auth/AuthManager.swift
// AuthManager          — defined in Core/Auth/AuthManager.swift
// AvatarView           — defined in Shared/Components/AvatarView.swift
// stripHTML            — defined in Shared/Components/PostCardView.swift
// relativeTimestamp    — defined in Shared/Components/PostCardView.swift

// MARK: - MastodonStatusContext

/// Response model for GET /api/v1/statuses/:id/context
/// NOTE: Add a `statusContext(id:)` method to MastodonAPIClient.swift returning this type.
struct MastodonStatusContext: Decodable {
    let ancestors: [MastodonStatus]
    let descendants: [MastodonStatus]
}

// MARK: - ThreadNetworkHelper
//
// Thin async helper for the status-context endpoint.
// Mirrors the conventions in MastodonAPIClient without requiring access to its
// private stored properties. Used only by MessageThreadViewModel.

private struct ThreadNetworkHelper {

    let instanceURL: URL
    let accessToken: String

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Fetches GET /api/v1/statuses/:id/context
    func statusContext(id: String) async throws -> MastodonStatusContext {
        var components = URLComponents(url: instanceURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/v1/statuses/\(id)/context"
        guard let url = components.url else {
            throw MastodonClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw MastodonClientError.httpError(statusCode: http.statusCode, body: body)
        }

        do {
            return try decoder.decode(MastodonStatusContext.self, from: data)
        } catch {
            throw MastodonClientError.decodingError(underlying: error)
        }
    }
}

// MARK: - MessageThreadViewModel

/// Observable view-model for a single DM thread.
///
/// Loads all statuses that belong to the conversation by fetching the context
/// of `lastStatus`, then filtering to `.direct` visibility only.
///
/// Sending prepends the authenticated user's @mention of the recipient and
/// submits via `createStatus(visibility: .direct)`.
@Observable
@MainActor
final class MessageThreadViewModel {

    // MARK: - Observable State

    /// The messages in this thread, sorted oldest-first for display.
    var messages: [MastodonStatus] = []

    /// `true` while the initial thread load is in flight.
    var isLoading: Bool = false

    /// The text the user is currently composing.
    var draftContent: String = ""

    /// `true` while a send request is in flight.
    var isSending: Bool = false

    /// Non-nil when the most recent operation produced an error.
    var error: Error?

    // MARK: - Internal State

    /// The conversation backing this view-model.
    let conversation: MastodonConversation

    private var client: MastodonAPIClient?
    private var networkHelper: ThreadNetworkHelper?

    /// The `acct` (handle) of the authenticated user — used for bubble alignment.
    private var ownAcct: String = ""

    /// @mention string to prepend to outgoing direct messages.
    private var recipientMention: String {
        guard let participant = conversation.otherParticipant else { return "" }
        let acct = participant.acct
        return acct.hasPrefix("@") ? acct : "@\(acct)"
    }

    // MARK: - Init

    init(conversation: MastodonConversation) {
        self.conversation = conversation
    }

    // MARK: - Setup

    /// Configures API helpers from the provided credential.
    /// Must be called before `load()` or `send()`.
    func setup(with credential: AccountCredential) {
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
        networkHelper = ThreadNetworkHelper(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
        ownAcct = credential.handle
    }

    // MARK: - Loading

    /// Loads the conversation's message history.
    ///
    /// 1. Immediately seeds the list with `lastStatus` for instant display.
    /// 2. Fetches the full status context (ancestors + descendants).
    /// 3. Combines, de-duplicates, and filters to `.direct` visibility only.
    func load() async {
        guard let networkHelper else { return }
        isLoading = true
        error = nil

        do {
            if let last = conversation.lastStatus {
                // Seed with the last status while the network call is in flight.
                if messages.isEmpty {
                    messages = [last]
                }

                let context = try await networkHelper.statusContext(id: last.id)

                let thread: [MastodonStatus] = (context.ancestors + [last] + context.descendants)
                    .filter { $0.visibility == .direct }

                // De-duplicate by ID, preserving order.
                var seen = Set<String>()
                messages = thread.filter { seen.insert($0.id).inserted }
            }
        } catch {
            // Non-fatal: leave any seeded messages visible.
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Sending

    /// Sends `draftContent` as a direct-message reply in this conversation thread.
    ///
    /// The recipient's @handle is automatically prepended when absent.
    /// On success the draft is cleared and the new status is appended locally.
    func send() async {
        guard let client else { return }
        let trimmed = draftContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSending else { return }

        isSending = true

        let fullContent: String
        if !recipientMention.isEmpty,
           !trimmed.lowercased().hasPrefix(recipientMention.lowercased()) {
            fullContent = "\(recipientMention) \(trimmed)"
        } else {
            fullContent = trimmed
        }

        let replyToId = messages.last?.id

        do {
            let sent = try await client.createStatus(
                content: fullContent,
                visibility: .direct,
                inReplyToId: replyToId
            )
            draftContent = ""
            messages.append(sent)
        } catch {
            self.error = error
        }

        isSending = false
    }

    // MARK: - Ownership

    /// `true` when the given status was authored by the authenticated user.
    func isOwnMessage(_ status: MastodonStatus) -> Bool {
        let acct = status.account.acct
        return acct == ownAcct ||
               acct.hasPrefix(ownAcct + "@") ||
               status.account.username == ownAcct
    }
}

// MARK: - MessageThreadView

/// Chat-bubble–style view for a single DM thread.
///
/// Own messages appear right-aligned in accent-colour bubbles.
/// Others' messages appear left-aligned with a gray bubble and an avatar.
/// A sticky bottom bar holds the compose field and send button.
struct MessageThreadView: View {

    // MARK: - State

    @State private var viewModel: MessageThreadViewModel
    @Environment(AuthManager.self) private var authManager

    private let bottomAnchorId = "MessageThreadBottom"

    // MARK: - Init

    init(conversation: MastodonConversation) {
        _viewModel = State(wrappedValue: MessageThreadViewModel(conversation: conversation))
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            messageScrollView
            Divider()
            inputBar
        }
        .navigationTitle(viewModel.conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.load()
        }
    }

    // MARK: - Message Scroll View

    private var messageScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        ProgressView()
                            .padding(.top, 32)
                    }

                    ForEach(viewModel.messages) { message in
                        messageBubble(for: message)
                            .id(message.id)
                    }

                    // Invisible anchor used for auto-scroll-to-bottom.
                    Color.clear
                        .frame(height: 1)
                        .id(bottomAnchorId)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 16)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
    }

    // MARK: - Message Bubble Dispatch

    @ViewBuilder
    private func messageBubble(for status: MastodonStatus) -> some View {
        let isOwn = viewModel.isOwnMessage(status)

        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 64)
                ownBubble(status: status)
            } else {
                otherBubble(status: status)
                Spacer(minLength: 64)
            }
        }
    }

    // MARK: - Own Bubble (right-aligned, blue)

    private func ownBubble(status: MastodonStatus) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(stripHTML(status.content))
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: MessageBubbleShape(isOwn: true))
                .textSelection(.enabled)

            Text(relativeTimestamp(from: status.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.trailing, 4)
        }
    }

    // MARK: - Other Bubble (left-aligned, gray)

    private func otherBubble(status: MastodonStatus) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            AvatarView(
                url: status.account.avatarURL,
                size: 32,
                shape: .circle
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(stripHTML(status.content))
                    .font(.body)
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color(.secondarySystemBackground),
                        in: MessageBubbleShape(isOwn: false)
                    )
                    .textSelection(.enabled)

                Text(relativeTimestamp(from: status.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $viewModel.draftContent, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
                .submitLabel(.send)
                .onSubmit {
                    Task { await viewModel.send() }
                }

            Button {
                Task { await viewModel.send() }
            } label: {
                let isEmpty = viewModel.draftContent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty
                if viewModel.isSending {
                    ProgressView()
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(isEmpty ? Color(.systemGray3) : Color.accentColor)
                }
            }
            .disabled(
                viewModel.draftContent
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty || viewModel.isSending
            )
            .animation(.easeInOut(duration: 0.15), value: viewModel.draftContent.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
    }
}

// MARK: - MessageBubbleShape

/// A rounded rectangle whose tail corner has a smaller radius to suggest a
/// speech bubble. Bottom-trailing is the tail for own messages;
/// bottom-leading is the tail for others'.
private struct MessageBubbleShape: Shape {

    let isOwn: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat    = 18 // main corner radius
        let tail: CGFloat = 5  // tail corner radius

        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading:     r,
                bottomLeading:  isOwn ? r    : tail,
                bottomTrailing: isOwn ? tail : r,
                topTrailing:    r
            )
        )
        return path
    }
}

// MARK: - Preview

#if DEBUG
#Preview("MessageThreadView") {
    NavigationStack {
        Text("MessageThreadView preview requires a MastodonConversation instance.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
            .navigationTitle("Thread")
    }
    .environment(AuthManager.shared)
}
#endif
