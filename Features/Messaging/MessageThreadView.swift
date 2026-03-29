// MessageThreadView.swift
// Rosemount
//
// Individual DM conversation thread view with chat-bubble layout and a
// bottom compose bar. Messages are Mastodon statuses with visibility=direct.
// End-to-end encryption uses the Double Ratchet protocol (DoubleRatchet.swift /
// E2EMessageService.swift) when both parties have published key bundles.
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
// E2EMessageService    — defined in Core/Crypto/E2EMessageService.swift

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

private struct ThreadNetworkHelper {

    let instanceURL: URL
    let accessToken: String

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

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

// MARK: - Decrypted Message Cache Entry

private struct DecryptedEntry {
    let statusId: String
    let plaintext: String
    let wasEncrypted: Bool
    var isCompatMode: Bool = false
}

// MARK: - MessageThreadViewModel

@Observable
@MainActor
final class MessageThreadViewModel {

    // MARK: - Observable State

    var messages: [MastodonStatus] = []
    var decryptedMessages: [String: DecryptedEntry] = [:]
    var isLoading: Bool = false
    var draftContent: String = ""
    var isSending: Bool = false
    var isEncryptionAvailable: Bool = false
    var useEncryption: Bool = true
    var error: Error?

    // MARK: - Internal State

    let conversation: MastodonConversation

    private var client: MastodonAPIClient?
    private var networkHelper: ThreadNetworkHelper?
    private var e2eService: E2EMessageService?
    private var ownAcct: String = ""

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

        let service = E2EMessageService(credential: credential)
        e2eService = service

        // Bootstrap the local key pair and publish in background; failures are non-fatal.
        Task {
            do {
                try await service.ensureIdentityKey()
                await service.publishPublicKey()
                isEncryptionAvailable = true
            } catch {
                isEncryptionAvailable = false
            }
        }
    }

    // MARK: - Loading

    func load() async {
        guard let networkHelper else { return }
        isLoading = true
        error = nil

        do {
            if let last = conversation.lastStatus {
                if messages.isEmpty { messages = [last] }

                let context = try await networkHelper.statusContext(id: last.id)
                let thread: [MastodonStatus] = (context.ancestors + [last] + context.descendants)
                    .filter { $0.visibility == .direct }

                var seen = Set<String>()
                messages = thread.filter { seen.insert($0.id).inserted }
            }
        } catch {
            self.error = error
        }

        isLoading = false

        // Decrypt any encrypted messages in the loaded thread.
        await decryptAll()
    }

    // MARK: - Decryption

    private func decryptAll() async {
        guard let service = e2eService else { return }
        for message in messages where decryptedMessages[message.id] == nil {
            await decryptStatus(message, service: service)
        }
    }

    private func decryptStatus(_ status: MastodonStatus, service: E2EMessageService) async {
        let encrypted = await service.isEncrypted(status)
        guard encrypted else {
            decryptedMessages[status.id] = DecryptedEntry(
                statusId: status.id,
                plaintext: stripHTML(status.content),
                wasEncrypted: false
            )
            return
        }
        let compat = await service.isCompatMode(status)
        do {
            if let plaintext = try await service.decryptMessage(status) {
                decryptedMessages[status.id] = DecryptedEntry(
                    statusId: status.id,
                    plaintext: plaintext,
                    wasEncrypted: true,
                    isCompatMode: compat
                )
            }
        } catch {
            decryptedMessages[status.id] = DecryptedEntry(
                statusId: status.id,
                plaintext: "⚠️ Unable to decrypt message.",
                wasEncrypted: true,
                isCompatMode: compat
            )
        }
    }

    // MARK: - Sending

    func send() async {
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
            let sent: MastodonStatus

            if useEncryption,
               isEncryptionAvailable,
               let service = e2eService,
               let recipient = conversation.otherParticipant {
                sent = try await service.sendEncryptedMessage(to: recipient, content: fullContent)
            } else if let client {
                sent = try await client.createStatus(
                    content: fullContent,
                    visibility: .direct,
                    inReplyToId: replyToId
                )
            } else {
                isSending = false
                return
            }

            draftContent = ""
            messages.append(sent)

            // Immediately cache the decrypted plaintext so it renders correctly.
            decryptedMessages[sent.id] = DecryptedEntry(
                statusId: sent.id,
                plaintext: trimmed,
                wasEncrypted: useEncryption && isEncryptionAvailable
            )
        } catch {
            self.error = error
        }

        isSending = false
    }

    // MARK: - Ownership

    func isOwnMessage(_ status: MastodonStatus) -> Bool {
        let acct = status.account.acct
        return acct == ownAcct ||
               acct.hasPrefix(ownAcct + "@") ||
               status.account.username == ownAcct
    }

    // MARK: - Display Helpers

    func displayText(for status: MastodonStatus) -> String {
        decryptedMessages[status.id]?.plaintext ?? stripHTML(status.content)
    }

    func wasEncrypted(_ status: MastodonStatus) -> Bool {
        decryptedMessages[status.id]?.wasEncrypted ?? false
    }

    func isCompatMode(_ status: MastodonStatus) -> Bool {
        decryptedMessages[status.id]?.isCompatMode ?? false
    }
}

// MARK: - MessageThreadView

struct MessageThreadView: View {

    @State private var viewModel: MessageThreadViewModel
    @Environment(AuthManager.self) private var authManager

    private let bottomAnchorId = "MessageThreadBottom"

    init(conversation: MastodonConversation) {
        _viewModel = State(wrappedValue: MessageThreadViewModel(conversation: conversation))
    }

    var body: some View {
        VStack(spacing: 0) {
            messageScrollView
            Divider()
            inputBar
        }
        .navigationTitle(viewModel.conversation.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                encryptionStatusButton
            }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.load()
        }
    }

    // MARK: - Encryption status button

    @ViewBuilder
    private var encryptionStatusButton: some View {
        if viewModel.isEncryptionAvailable {
            Button {
                viewModel.useEncryption.toggle()
            } label: {
                Image(systemName: viewModel.useEncryption ? "lock.fill" : "lock.open")
                    .foregroundStyle(viewModel.useEncryption ? Color.green : Color.secondary)
                    .accessibilityLabel(viewModel.useEncryption ? "Encryption on" : "Encryption off")
            }
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

    // MARK: - Own Bubble

    private func ownBubble(status: MastodonStatus) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(viewModel.displayText(for: status))
                .font(.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: MessageBubbleShape(isOwn: true))
                .textSelection(.enabled)

            HStack(spacing: 4) {
                if viewModel.wasEncrypted(status) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(viewModel.isCompatMode(status) ? Color.yellow : Color.green)
                        .accessibilityLabel(viewModel.isCompatMode(status) ? "Encrypted (unverified)" : "Encrypted")
                        .help(viewModel.isCompatMode(status)
                              ? "Messages are encrypted but peer verification is unavailable"
                              : "End-to-end encrypted")
                }
                Text(relativeTimestamp(from: status.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.trailing, 4)
        }
    }

    // MARK: - Other Bubble

    private func otherBubble(status: MastodonStatus) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            AvatarView(
                url: status.account.avatarURL,
                size: 32,
                shape: .circle
            )

            VStack(alignment: .leading, spacing: 3) {
                Text(viewModel.displayText(for: status))
                    .font(.body)
                    .foregroundStyle(Color(.label))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Color(.secondarySystemBackground),
                        in: MessageBubbleShape(isOwn: false)
                    )
                    .textSelection(.enabled)

                HStack(spacing: 4) {
                    if viewModel.wasEncrypted(status) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(viewModel.isCompatMode(status) ? Color.yellow : Color.green)
                            .accessibilityLabel(viewModel.isCompatMode(status) ? "Encrypted (unverified)" : "Encrypted")
                            .help(viewModel.isCompatMode(status)
                                  ? "Messages are encrypted but peer verification is unavailable"
                                  : "End-to-end encrypted")
                    }
                    Text(relativeTimestamp(from: status.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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

private struct MessageBubbleShape: Shape {

    let isOwn: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat    = 18
        let tail: CGFloat = 5

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
