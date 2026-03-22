// EditProfileView.swift
// Rosemount
//
// Edit-own-profile screen (Phase 2).
// Lets the authenticated user update their display name, bio, avatar, and header.
//
// Types referenced from other files:
//   MastodonAPIClient   — Core/Mastodon/MastodonAPIClient.swift
//   MastodonAccount     — Core/Mastodon/Models/MastodonAccount.swift
//   AccountCredential   — Core/Auth/AuthManager.swift
//   AuthManager         — Core/Auth/AuthManager.swift
//   AvatarView          — Shared/Components/AvatarView.swift
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import PhotosUI

// MARK: - EditProfileViewModel

@Observable
@MainActor
final class EditProfileViewModel {

    // MARK: - Bindable State

    var displayName: String = ""
    var bio: String = ""
    /// Editable profile metadata fields (Mastodon supports up to 4).
    var profileFields: [(name: String, value: String)] = []
    var avatarImage: UIImage? = nil
    var headerImage: UIImage? = nil
    var isSaving: Bool = false
    var error: Error? = nil
    var didSave: Bool = false

    // MARK: - Private

    private var client: MastodonAPIClient?

    // MARK: - Setup

    /// Pre-fills the editable fields from the given account and stores the credential.
    func setup(with account: MastodonAccount, credential: AccountCredential) {
        displayName = account.displayName
        // Strip any HTML from the bio — the server returns note as HTML.
        bio = stripHTML(account.note)
        // Pre-populate profile fields, stripping any HTML from values.
        profileFields = account.fields.map { (name: $0.name, value: stripHTML($0.value)) }
        // Ensure at least one empty row so the user can add a field immediately.
        if profileFields.isEmpty { profileFields = [("", "")] }
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Save

    /// Sends a PATCH update_credentials request and sets `didSave` on success.
    func save(with credential: AccountCredential) async {
        guard let client else { return }

        isSaving = true
        error = nil

        let avatarJPEG = avatarImage?.jpegData(compressionQuality: 0.85)
        let headerJPEG = headerImage?.jpegData(compressionQuality: 0.85)

        do {
            // Filter out entirely-empty rows before sending.
            let nonEmptyFields = profileFields.filter { !$0.name.isEmpty || !$0.value.isEmpty }
            _ = try await client.updateCredentials(
                displayName: displayName,
                note: bio,
                avatarData: avatarJPEG,
                headerData: headerJPEG,
                fields: nonEmptyFields.isEmpty ? nil : nonEmptyFields
            )
            didSave = true
        } catch {
            self.error = error
        }

        isSaving = false
    }
}

// MARK: - EditProfileView

/// Full-screen sheet for editing the authenticated user's Mastodon profile.
struct EditProfileView: View {

    // MARK: - Properties

    private let account: MastodonAccount

    @State private var viewModel = EditProfileViewModel()

    // PhotosPicker selection state
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var headerPickerItem: PhotosPickerItem? = nil

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // MARK: - Init

    init(account: MastodonAccount) {
        self.account = account
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // ── Photos ────────────────────────────────────────────────
                Section {
                    headerPickerRow
                    avatarPickerRow
                } header: {
                    Text("Photos")
                }

                // ── Profile ───────────────────────────────────────────────
                Section {
                    TextField("Display name", text: $viewModel.displayName)
                        .autocorrectionDisabled()

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Bio")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.bio)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Profile")
                }

                // ── Profile fields ────────────────────────────────────────
                Section {
                    ForEach(viewModel.profileFields.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            TextField("Label", text: Binding(
                                get: { viewModel.profileFields[i].name },
                                set: { viewModel.profileFields[i].name = $0 }
                            ))
                            .frame(width: 100)
                            .foregroundStyle(.secondary)
                            .autocorrectionDisabled()

                            Divider()

                            TextField("Content", text: Binding(
                                get: { viewModel.profileFields[i].value },
                                set: { viewModel.profileFields[i].value = $0 }
                            ))
                            .autocorrectionDisabled()
                        }
                    }
                    .onDelete { indexSet in
                        viewModel.profileFields.remove(atOffsets: indexSet)
                        // Keep at least one row visible.
                        if viewModel.profileFields.isEmpty {
                            viewModel.profileFields = [("", "")]
                        }
                    }

                    if viewModel.profileFields.count < 4 {
                        Button {
                            viewModel.profileFields.append(("", ""))
                        } label: {
                            Label("Add field", systemImage: "plus.circle")
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("Profile fields")
                } footer: {
                    Text("Up to 4 key–value fields shown on your profile. URLs are automatically verified.")
                        .font(.caption)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isSaving)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Group {
                        if viewModel.isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button("Save") {
                                guard let credential = authManager.activeAccount else { return }
                                Task { await viewModel.save(with: credential) }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            // Error alert
            .alert("Couldn't Save Profile", isPresented: .constant(viewModel.error != nil)) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "An unknown error occurred.")
            }
            // React to PhotosPicker avatar selection
            .onChange(of: avatarPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.avatarImage = image
                    }
                }
            }
            // React to PhotosPicker header selection
            .onChange(of: headerPickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        viewModel.headerImage = image
                    }
                }
            }
            // Dismiss automatically after a successful save
            .onChange(of: viewModel.didSave) { _, saved in
                if saved { dismiss() }
            }
        }
        // Pre-fill from the account on first appearance.
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: account, credential: credential)
        }
    }

    // MARK: - Header Picker Row

    private var headerPickerRow: some View {
        PhotosPicker(selection: $headerPickerItem, matching: .images) {
            ZStack(alignment: .bottomLeading) {
                // Header preview
                Group {
                    if let image = viewModel.headerImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        AsyncImage(url: account.headerURL) { phase in
                            switch phase {
                            case .success(let img):
                                img.resizable().aspectRatio(contentMode: .fill)
                            default:
                                Color(.systemGray5)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Edit badge
                editBadge(systemImage: "photo.badge.plus")
                    .padding(8)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    // MARK: - Avatar Picker Row

    private var avatarPickerRow: some View {
        HStack {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    // Avatar preview
                    if let image = viewModel.avatarImage {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 80)
                            .clipShape(Circle())
                    } else {
                        AvatarView(url: account.avatarURL, size: 80, shape: .circle)
                    }

                    // Edit badge
                    editBadge(systemImage: "pencil.circle.fill")
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Avatar")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Tap to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Edit Badge

    private func editBadge(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 22))
            .foregroundStyle(.white, Color.accentColor)
            .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("EditProfileView") {
    // A lightweight stand-in when we have no live account.
    Text("EditProfileView requires a live AuthManager environment.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding()
}
#endif
