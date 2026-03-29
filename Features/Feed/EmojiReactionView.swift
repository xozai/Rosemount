// Features/Feed/EmojiReactionView.swift
// Emoji reaction picker and reaction bar for posts

import SwiftUI

let quickReactEmojis = ["❤️", "🔥", "😂", "😮", "😢", "👏", "🙌", "🤔"]

// MARK: - ViewModel

@Observable
@MainActor
final class EmojiReactionViewModel {
    var reactions: [ReactionSummary] = []
    var isReacting: Bool = false
    var error: Error?

    func react(emoji: String, statusId: String, credential: AccountCredential) async {
        // Optimistic update
        if let idx = reactions.firstIndex(where: { $0.emoji == emoji }) {
            if reactions[idx].hasReacted { return }
            reactions[idx] = ReactionSummary(
                emoji: emoji,
                count: reactions[idx].count + 1,
                hasReacted: true
            )
        } else {
            reactions.append(ReactionSummary(emoji: emoji, count: 1, hasReacted: true))
        }

        do {
            var req = URLRequest(url: credential.instanceURL.appendingPathComponent("api/v1/statuses/\(statusId)/react"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder().encode(["emoji": emoji])
            _ = try await URLSession.shared.data(for: req)
        } catch {
            // Revert
            if let idx = reactions.firstIndex(where: { $0.emoji == emoji }) {
                reactions[idx] = ReactionSummary(
                    emoji: emoji,
                    count: max(0, reactions[idx].count - 1),
                    hasReacted: false
                )
                if reactions[idx].count == 0 { reactions.remove(at: idx) }
            }
            self.error = error
        }
    }

    func unreact(emoji: String, statusId: String, credential: AccountCredential) async {
        // Optimistic update
        if let idx = reactions.firstIndex(where: { $0.emoji == emoji }) {
            let newCount = reactions[idx].count - 1
            if newCount <= 0 {
                reactions.remove(at: idx)
            } else {
                reactions[idx] = ReactionSummary(emoji: emoji, count: newCount, hasReacted: false)
            }
        }

        do {
            var req = URLRequest(url: credential.instanceURL.appendingPathComponent("api/v1/statuses/\(statusId)/react/\(emoji)"))
            req.httpMethod = "DELETE"
            req.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            _ = try await URLSession.shared.data(for: req)
        } catch {
            // Revert — re-add
            reactions.append(ReactionSummary(emoji: emoji, count: 1, hasReacted: true))
            self.error = error
        }
    }
}

// MARK: - Reaction Bar

struct EmojiReactionBar: View {
    let reactions: [ReactionSummary]
    let onReact: (String) -> Void
    let onUnreact: (String) -> Void

    var body: some View {
        if reactions.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(reactions.filter { $0.count > 0 }) { reaction in
                        ReactionPill(reaction: reaction) {
                            if reaction.hasReacted {
                                onUnreact(reaction.emoji)
                            } else {
                                onReact(reaction.emoji)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct ReactionPill: View {
    let reaction: ReactionSummary
    let onTap: () -> Void
    @State private var scale: Double = 1.0

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { scale = 1.3 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) { scale = 1.0 }
            }
            onTap()
        } label: {
            HStack(spacing: 3) {
                Text(reaction.emoji).font(.caption)
                Text("\(reaction.count)").font(.caption.bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                reaction.hasReacted
                ? Color.blue.opacity(0.15)
                : Color.secondary.opacity(0.1)
            )
            .overlay(
                Capsule()
                    .stroke(reaction.hasReacted ? Color.blue : Color.clear, lineWidth: 1.2)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .accessibilityLabel(
            reaction.hasReacted
                ? "Remove \(reaction.emoji) reaction, \(reaction.count) total"
                : "React with \(reaction.emoji), \(reaction.count) total"
        )
    }
}

// MARK: - Emoji Picker

struct EmojiPickerView: View {
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible()), count: 4)

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(quickReactEmojis, id: \.self) { emoji in
                    Button {
                        onSelect(emoji)
                        dismiss()
                    } label: {
                        Text(emoji).font(.system(size: 32))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("React with \(emoji)")
                }
            }
            .padding()
            .navigationTitle("React")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.height(200)])
    }
}

// MARK: - PostCardWithReactions wrapper

struct PostCardWithReactions: View {
    let status: MastodonStatus
    let credential: AccountCredential?
    @State private var viewModel = EmojiReactionViewModel()
    @State private var showingPicker = false

    var body: some View {
        VStack(spacing: 0) {
            PostCardView(status: status)

            if !viewModel.reactions.isEmpty {
                EmojiReactionBar(
                    reactions: viewModel.reactions,
                    onReact: { emoji in
                        guard let cred = credential else { return }
                        Task { await viewModel.react(emoji: emoji, statusId: status.id, credential: cred) }
                    },
                    onUnreact: { emoji in
                        guard let cred = credential else { return }
                        Task { await viewModel.unreact(emoji: emoji, statusId: status.id, credential: cred) }
                    }
                )
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
        }
        .onLongPressGesture(minimumDuration: 0.4) {
            showingPicker = true
        }
        .sheet(isPresented: $showingPicker) {
            EmojiPickerView { emoji in
                guard let cred = credential else { return }
                Task { await viewModel.react(emoji: emoji, statusId: status.id, credential: cred) }
            }
        }
        .onAppear {
            // Populate reactions from status if available (Pleroma/Glitch field)
            // viewModel.reactions = status.reactions ?? []
        }
    }
}
