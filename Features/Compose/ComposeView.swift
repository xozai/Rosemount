// ComposeView.swift
// Rosemount
//
// Post composer sheet. Presents a TextEditor for the post body,
// an optional content-warning field, a character counter,
// a visibility picker, and Cancel / Post toolbar buttons.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// ComposeViewModel  — defined in Features/Compose/ComposeViewModel.swift
// AuthManager       — defined in Core/Auth/AuthManager.swift
// AccountCredential — defined in Core/Auth/AuthManager.swift
// AvatarView        — defined in Shared/Components/AvatarView.swift
// MastodonVisibility — defined in Core/Mastodon/Models/MastodonStatus.swift

// MARK: - ComposeView

struct ComposeView: View {

    // MARK: - State

    @State private var viewModel = ComposeViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - Focus

    @FocusState private var isContentFocused: Bool

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Content warning field (shown above the main editor when active)
                if viewModel.hasSpoilerText {
                    contentWarningField
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                // Main compose row: avatar + text editor
                HStack(alignment: .top, spacing: 10) {
                    if let account = authManager.activeAccount {
                        AvatarView(url: account.avatarURL, size: 36, shape: .circle)
                    }

                    TextEditor(text: $viewModel.content)
                        .font(.body)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .focused($isContentFocused)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if viewModel.content.isEmpty {
                                Text("What's on your mind?")
                                    .foregroundStyle(Color(.placeholderText))
                                    .font(.body)
                                    .padding(.top, 8)
                                    .padding(.leading, 5)
                                    .allowsHitTesting(false)
                            }
                        }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                Divider()
                    .padding(.top, 8)

                // Bottom toolbar
                HStack(spacing: 16) {

                    // Photo attachment — disabled until Phase 2
                    Button {
                        // TODO: Phase 2 — media picker
                    } label: {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                    }
                    .disabled(true)
                    .foregroundStyle(Color(.systemGray3))

                    // Location — disabled until Phase 4
                    Button {
                        // TODO: Phase 4 — location tagging
                    } label: {
                        Image(systemName: "location")
                            .font(.title3)
                    }
                    .disabled(true)
                    .foregroundStyle(Color(.systemGray3))

                    // Content warning toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            viewModel.hasSpoilerText.toggle()
                        }
                    } label: {
                        Image(systemName: viewModel.hasSpoilerText ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                            .font(.title3)
                    }
                    .foregroundStyle(viewModel.hasSpoilerText ? Color.orange : Color(.systemGray))

                    Spacer()

                    // Character count
                    CharacterCountView(remaining: viewModel.remainingCharacters)

                    // Visibility picker
                    visibilityPickerMenu
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Spacer()
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.discardDraft()
                        dismiss()
                    }
                }

                // Post
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await viewModel.post() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canPost)
                }
            }
            .overlay {
                // Posting spinner overlay
                if viewModel.isPosting {
                    Color.black.opacity(0.1)
                        .ignoresSafeArea()
                    ProgressView("Posting…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .alert("Post Failed", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK", role: .cancel) { viewModel.error = nil }
            } message: {
                if let error = viewModel.error {
                    Text(error.localizedDescription)
                }
            }
        }
        .task {
            guard let account = authManager.activeAccount else { return }
            viewModel.setup(with: account)
            isContentFocused = true
        }
        .onChange(of: viewModel.didPost) { _, posted in
            if posted { dismiss() }
        }
    }

    // MARK: - Subviews

    private var contentWarningField: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.subheadline)

            TextField("Content warning…", text: $viewModel.spoilerText)
                .font(.subheadline)
                .submitLabel(.next)
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var visibilityPickerMenu: some View {
        Menu {
            Button {
                viewModel.visibility = .public
            } label: {
                Label("Public", systemImage: "globe")
            }

            Button {
                viewModel.visibility = .unlisted
            } label: {
                Label("Unlisted", systemImage: "lock.open")
            }

            Button {
                viewModel.visibility = .private
            } label: {
                Label("Followers only", systemImage: "person")
            }

            Button {
                viewModel.visibility = .direct
            } label: {
                Label("Direct message", systemImage: "envelope")
            }
        } label: {
            Image(systemName: visibilityIcon(for: viewModel.visibility))
                .font(.title3)
                .foregroundStyle(Color(.systemGray))
        }
    }

    // MARK: - Helpers

    private func visibilityIcon(for visibility: MastodonVisibility) -> String {
        switch visibility {
        case .public:    return "globe"
        case .unlisted:  return "lock.open"
        case .private:   return "person"
        case .direct:    return "envelope"
        }
    }
}

// MARK: - CharacterCountView

/// Displays remaining characters available for a post.
/// Text turns orange below 50 and red below 20.
struct CharacterCountView: View {

    let remaining: Int

    private var textColor: Color {
        if remaining < 20  { return .red }
        if remaining < 50  { return .orange }
        return .secondary
    }

    var body: some View {
        Text("\(remaining)")
            .font(.subheadline.monospacedDigit())
            .fontWeight(remaining < 20 ? .semibold : .regular)
            .foregroundStyle(textColor)
            .contentTransition(.numericText())
            .animation(.default, value: remaining)
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    ComposeView()
        .environment(AuthManager.shared)
}
#endif
