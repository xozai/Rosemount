// ConversationsView.swift
// Rosemount
//
// Direct-messaging conversation list with swipe-to-delete, pull-to-refresh,
// and a compose button to start a new DM.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// ConversationsViewModel — defined in Features/Messaging/ConversationsViewModel.swift
// MastodonConversation   — defined in Core/Mastodon/Models/MastodonConversation.swift
// MessageThreadView      — defined in Features/Messaging/MessageThreadView.swift
// NewDMView              — defined in Features/Messaging/NewDMView.swift
// AvatarView             — defined in Shared/Components/AvatarView.swift
// AuthManager            — defined in Core/Auth/AuthManager.swift
// relativeTimestamp      — defined in Shared/Components/PostCardView.swift
// stripHTML              — defined in Shared/Components/PostCardView.swift

// MARK: - ConversationsView

/// Root view for the direct-messaging tab.
///
/// Shows a list of conversation threads, sorted newest-first.
/// Pull-to-refresh reloads from the server.
/// A compose button in the toolbar opens `NewDMView` as a sheet.
struct ConversationsView: View {

    // MARK: - State

    @State private var viewModel = ConversationsViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var showingNewDM = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            conversationContent
                .navigationTitle("Messages")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .sheet(isPresented: $showingNewDM) {
                    NewDMView()
                        .environment(authManager)
                }
                .task {
                    guard let credential = authManager.activeAccount else { return }
                    viewModel.setup(with: credential)
                    await viewModel.refresh()
                }
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var conversationContent: some View {
        if viewModel.isLoading && viewModel.conversations.isEmpty {
            loadingView
        } else if let error = viewModel.error, viewModel.conversations.isEmpty {
            errorView(error)
        } else if viewModel.conversations.isEmpty {
            emptyStateView
        } else {
            conversationList
        }
    }

    // MARK: - Conversation List

    private var conversationList: some View {
        List {
            ForEach(viewModel.conversations) { conversation in
                NavigationLink(destination: MessageThreadView(conversation: conversation)) {
                    ConversationRowView(conversation: conversation)
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                .listRowSeparator(.visible, edges: .bottom)
                .onAppear {
                    // Mark as read when the row becomes visible (best-effort).
                    if conversation.unread {
                        Task { await viewModel.markRead(conversation: conversation) }
                    }
                }
            }
            .onDelete { offsets in
                viewModel.deleteConversations(at: offsets)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView("Loading messages…")
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Failed to load messages")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "envelope")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No messages yet")
                .font(.headline)
            Text("No messages yet. Start a conversation!")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("New Message") {
                showingNewDM = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNewDM = true
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .accessibilityLabel("New message")
        }
    }
}

// MARK: - ConversationRowView

/// A single row in the `ConversationsView` list.
///
/// Shows the other participant's avatar, the conversation title (bold when
/// unread), a one-line preview of the last status, a timestamp, and an
/// unread indicator dot.
struct ConversationRowView: View {

    // MARK: - Properties

    let conversation: MastodonConversation

    // MARK: - Init

    init(conversation: MastodonConversation) {
        self.conversation = conversation
    }

    // MARK: - Body

    var body: some View {
        HStack(alignment: .top, spacing: 12) {

            // Avatar of the primary other participant
            AvatarView(
                url: conversation.otherParticipant?.avatarURL,
                size: 44,
                shape: .circle
            )
            .padding(.top, 2)

            // Text column
            VStack(alignment: .leading, spacing: 3) {
                // Title row: display name + timestamp + unread dot
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.displayTitle)
                        .font(.subheadline)
                        .fontWeight(conversation.unread ? .bold : .regular)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if let lastStatus = conversation.lastStatus {
                        Text(relativeTimestamp(from: lastStatus.createdAt))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Last message preview
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let lastStatus = conversation.lastStatus {
                        Text(stripHTML(lastStatus.content))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    } else {
                        Text("No messages yet")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .italic()
                    }

                    Spacer(minLength: 0)

                    // Unread dot indicator
                    if conversation.unread {
                        Circle()
                            .fill(Color.accentColor)
                            .frame(width: 8, height: 8)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("ConversationsView") {
    ConversationsView()
        .environment(AuthManager.shared)
}
#endif
