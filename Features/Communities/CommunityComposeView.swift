// CommunityComposeView.swift
// Rosemount
//
// Post composer scoped to a specific community.
// A thin, focused wrapper around the community posting API that mirrors the
// existing ComposeView UI conventions — avatar, TextEditor, character counter,
// visibility picker, Cancel / Post toolbar — but routes the post to the
// community feed endpoint instead of the home timeline.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// CommunityAPIClient  — Core/Communities/CommunityAPIClient.swift
// MastodonVisibility  — Core/Mastodon/Models/MastodonStatus.swift
// AuthManager         — Core/Auth/AuthManager.swift
// AccountCredential   — Core/Auth/AuthManager.swift
// AvatarView          — Shared/Components/AvatarView.swift
// CharacterCountView  — Features/Compose/ComposeView.swift

// MARK: - CommunityComposeView

struct CommunityComposeView: View {

    // MARK: Init

    private let communitySlug: String
    private let communityName: String

    init(communitySlug: String, communityName: String) {
        self.communitySlug = communitySlug
        self.communityName = communityName
    }

    // MARK: State

    @State private var content: String = ""
    @State private var visibility: MastodonVisibility = .public
    @State private var isPosting: Bool = false
    @State private var error: Error? = nil
    @State private var didPost: Bool = false

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @FocusState private var isContentFocused: Bool

    // MARK: Private

    private var client: CommunityAPIClient? {
        guard let credential = authManager.activeAccount else { return nil }
        return CommunityAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Character limit (matches Mastodon / community API convention)

    private static let characterLimit = 500

    private var characterCount: Int { content.count }
    private var remainingCharacters: Int { Self.characterLimit - characterCount }

    private var canPost: Bool {
        !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && remainingCharacters >= 0
            && !isPosting
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // Avatar + text editor row
                HStack(alignment: .top, spacing: 10) {
                    if let account = authManager.activeAccount {
                        AvatarView(url: account.avatarURL, size: 36, shape: .circle)
                    }

                    TextEditor(text: $content)
                        .font(.body)
                        .frame(minHeight: 120, alignment: .topLeading)
                        .focused($isContentFocused)
                        .scrollContentBackground(.hidden)
                        .overlay(alignment: .topLeading) {
                            if content.isEmpty {
                                Text("Share something with \(communityName)…")
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

                // "Posting to <community>" caption
                HStack {
                    Image(systemName: "person.3.fill")
                        .font(.caption2)
                    Text("Posting to \(communityName)")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)

                Divider()
                    .padding(.top, 10)

                // Bottom bar: character count + visibility picker
                HStack(spacing: 12) {
                    Spacer()

                    CharacterCountView(remaining: remainingCharacters)

                    visibilityPickerMenu
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Spacer()
            }
            .navigationTitle("New Community Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                // Post
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task { await post() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!canPost)
                }
            }
            // Posting overlay
            .overlay {
                if isPosting {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()
                    ProgressView("Posting…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            // Error alert
            .alert("Post Failed", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK", role: .cancel) { error = nil }
            } message: {
                if let error {
                    Text(error.localizedDescription)
                }
            }
        }
        .task {
            isContentFocused = true
        }
        .onChange(of: didPost) { _, posted in
            if posted { dismiss() }
        }
    }

    // MARK: - Visibility picker

    private var visibilityPickerMenu: some View {
        Menu {
            Button {
                visibility = .public
            } label: {
                Label("Public", systemImage: "globe")
            }

            Button {
                visibility = .unlisted
            } label: {
                Label("Unlisted", systemImage: "lock.open")
            }

            Button {
                visibility = .private
            } label: {
                Label("Followers only", systemImage: "person")
            }
        } label: {
            Image(systemName: visibilityIcon(for: visibility))
                .font(.title3)
                .foregroundStyle(Color(.systemGray))
        }
    }

    private func visibilityIcon(for visibility: MastodonVisibility) -> String {
        switch visibility {
        case .public:    return "globe"
        case .unlisted:  return "lock.open"
        case .private:   return "person"
        case .direct:    return "envelope"
        }
    }

    // MARK: - Post action

    private func post() async {
        guard canPost, let client else { return }

        isPosting = true
        error = nil

        do {
            _ = try await client.postToCommunity(
                slug: communitySlug,
                content: content,
                mediaIds: [],
                visibility: visibility.rawValue
            )
            content = ""
            didPost = true
        } catch {
            self.error = error
        }

        isPosting = false
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CommunityComposeView") {
    CommunityComposeView(
        communitySlug: "softball-league",
        communityName: "Springfield Softball League"
    )
    .environment(AuthManager.shared)
}
#endif
