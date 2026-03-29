// NewDMView.swift
// Rosemount
//
// Compose and send a new direct message to any Mastodon handle.
// Presented as a modal sheet from ConversationsView.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonAPIClient  — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonVisibility — defined in Core/Mastodon/Models/MastodonStatus.swift
// AuthManager        — defined in Core/Auth/AuthManager.swift
// AccountCredential  — defined in Core/Auth/AuthManager.swift

// MARK: - NewDMView

/// A modal form for composing a brand-new direct message.
///
/// The user provides a recipient handle (e.g. `@alice@mastodon.social`) and
/// an initial message body. On Send, the view calls `createStatus` with
/// `visibility: .direct` and prepends the @mention automatically.
/// The sheet dismisses on success.
struct NewDMView: View {

    // MARK: - State

    @State private var recipientHandle: String = ""
    @State private var initialMessage: String = ""
    @State private var isSending: Bool = false
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    // MARK: - Computed

    private var canSend: Bool {
        !recipientHandle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !initialMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSending
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                recipientSection
                messageSection

                if let errorMessage {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .disabled(isSending)
        }
    }

    // MARK: - Sections

    private var recipientSection: some View {
        Section {
            TextField("@user@instance.social", text: $recipientHandle)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: recipientHandle) { _, _ in
                    // Clear any previous send error when the user edits the fields.
                    errorMessage = nil
                }
        } header: {
            Text("To")
        } footer: {
            Text("Enter the full Mastodon handle, e.g. @alice@mastodon.social")
                .font(.caption)
        }
    }

    private var messageSection: some View {
        Section {
            TextEditor(text: $initialMessage)
                .frame(minHeight: 100)
                .onChange(of: initialMessage) { _, _ in
                    errorMessage = nil
                }
        } header: {
            Text("Message")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                dismiss()
            }
        }

        ToolbarItem(placement: .confirmationAction) {
            Button("Send") {
                Task { await sendMessage() }
            }
            .disabled(!canSend)
            .overlay {
                if isSending {
                    ProgressView()
                        .tint(.accentColor)
                }
            }
        }
    }

    // MARK: - Send Action

    private func sendMessage() async {
        guard let credential = authManager.activeAccount else {
            errorMessage = "No active account. Please sign in."
            return
        }

        let handle = recipientHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !handle.isEmpty else {
            errorMessage = "Please enter a recipient handle."
            return
        }
        guard !body.isEmpty else {
            errorMessage = "Please write a message."
            return
        }

        isSending = true
        errorMessage = nil

        // Normalise the recipient handle — ensure it starts with @.
        let mention = handle.hasPrefix("@") ? handle : "@\(handle)"

        // Build the full status content: @recipient <message>
        let fullContent = "\(mention) \(body)"

        let client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )

        do {
            _ = try await client.createStatus(
                content: fullContent,
                visibility: .direct
            )
            // Success — dismiss the sheet.
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSending = false
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("NewDMView") {
    NewDMView()
        .environment(AuthManager.shared)
}
#endif
