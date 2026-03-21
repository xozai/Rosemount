// CommunitySettingsView.swift
// Rosemount
//
// Admin settings screen for a community.
// Allows editing name, description, privacy, avatar, header image,
// and provides access to invite management and destructive delete.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import PhotosUI
import Observation

// RosemountCommunity  — Core/Communities/Models/RosemountCommunity.swift
// CommunityAPIClient  — Core/Communities/CommunityAPIClient.swift
// AccountCredential   — Core/Auth/AuthManager.swift
// AuthManager         — Core/Auth/AuthManager.swift
// CommunityInviteView — Features/Communities/CommunityInviteView.swift

// MARK: - CommunitySettingsViewModel

@Observable
@MainActor
final class CommunitySettingsViewModel {

    // MARK: State reflecting the community being edited

    var community: RosemountCommunity
    var name: String
    var description: String
    var isPrivate: Bool

    // Image pickers (set by PhotosPicker selections)
    var avatarImage: UIImage? = nil
    var headerImage: UIImage? = nil

    // Operation flags
    var isSaving: Bool = false
    var isDeleting: Bool = false
    var error: Error? = nil
    var didSave: Bool = false
    var showDeleteConfirmation: Bool = false
    var didDelete: Bool = false

    // MARK: Private

    private var client: CommunityAPIClient?

    // MARK: - Init

    init(community: RosemountCommunity) {
        self.community = community
        self.name = community.name
        self.description = community.description
        self.isPrivate = community.isPrivate
    }

    // MARK: - Setup

    /// Configures the underlying API client from an authenticated credential.
    func setup(with credential: AccountCredential) {
        client = CommunityAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Save

    /// Persists edits to the server via `PATCH /api/v1/communities/:slug`.
    func save() async {
        guard let client, !isSaving else { return }
        isSaving = true
        error = nil

        do {
            let avatarData  = avatarImage?.jpegData(compressionQuality: 0.85)
            let headerData  = headerImage?.jpegData(compressionQuality: 0.85)

            let updated = try await client.updateCommunity(
                slug: community.slug,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate: isPrivate,
                avatarData: avatarData,
                headerData: headerData
            )
            community = updated
            didSave = true
        } catch {
            self.error = error
        }

        isSaving = false
    }

    // MARK: - Delete

    /// Permanently deletes the community. Only admins may call this.
    func deleteCommunity() async {
        guard let client, !isDeleting else { return }
        isDeleting = true
        error = nil

        do {
            try await client.deleteCommunity(slug: community.slug)
            didDelete = true
        } catch {
            self.error = error
        }

        isDeleting = false
    }

    // MARK: - Helpers

    /// `true` when the form has unsaved changes relative to the server state.
    var hasChanges: Bool {
        name != community.name ||
        description != community.description ||
        isPrivate != community.isPrivate ||
        avatarImage != nil ||
        headerImage != nil
    }

    /// `true` when the form is valid enough to submit.
    var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        hasChanges &&
        !isSaving
    }
}

// MARK: - CommunitySettingsView

struct CommunitySettingsView: View {

    // MARK: Init

    private let community: RosemountCommunity

    init(community: RosemountCommunity) {
        self.community = community
        _viewModel = State(initialValue: CommunitySettingsViewModel(community: community))
    }

    // MARK: State

    @State private var viewModel: CommunitySettingsViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // PhotosPicker selection items
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var headerPickerItem: PhotosPickerItem? = nil

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {

                // MARK: Appearance
                Section("Appearance") {
                    // Header image picker
                    headerPickerRow

                    // Avatar image picker
                    avatarPickerRow
                }

                // MARK: Details
                Section("Details") {
                    TextField("Name", text: $viewModel.name)
                        .autocorrectionDisabled(false)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                }

                // MARK: Privacy
                Section {
                    Toggle("Private (invite-only)", isOn: $viewModel.isPrivate)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text(viewModel.isPrivate
                         ? "Only invited users can join and see community content."
                         : "Anyone can discover and join this community.")
                }

                // MARK: Invites
                Section("Invites") {
                    NavigationLink {
                        CommunityInviteView(slug: community.slug)
                            .environment(authManager)
                    } label: {
                        Label("Manage Invites", systemImage: "link.badge.plus")
                    }
                }

                // MARK: Danger Zone
                Section {
                    Button(role: .destructive) {
                        viewModel.showDeleteConfirmation = true
                    } label: {
                        HStack {
                            if viewModel.isDeleting {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Delete Community")
                                .foregroundStyle(.red)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .disabled(viewModel.isDeleting)
                } header: {
                    Text("Danger Zone")
                        .foregroundStyle(.red)
                } footer: {
                    Text("Deleting a community is permanent and cannot be undone.")
                }
            }
            .navigationTitle("Community Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await viewModel.save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                    .overlay {
                        if viewModel.isSaving {
                            ProgressView()
                        }
                    }
                }
            }
            // Delete confirmation dialog
            .confirmationDialog(
                "Delete \"\(viewModel.community.name)\"?",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Community", role: .destructive) {
                    Task { await viewModel.deleteCommunity() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action is permanent. All posts, members, and invites will be lost.")
            }
            // Error alert
            .alert("Error", isPresented: Binding(
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
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
        }
        // Handle successful save feedback
        .onChange(of: viewModel.didSave) { _, saved in
            if saved {
                // Brief delay so the user sees the success state before the sheet closes.
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    dismiss()
                }
            }
        }
        // Navigate away after delete
        .onChange(of: viewModel.didDelete) { _, deleted in
            if deleted { dismiss() }
        }
        // Load selected avatar image
        .onChange(of: avatarPickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                viewModel.avatarImage = image
            }
        }
        // Load selected header image
        .onChange(of: headerPickerItem) { _, newItem in
            Task {
                guard let item = newItem,
                      let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data) else { return }
                viewModel.headerImage = image
            }
        }
    }

    // MARK: - Header image picker row

    private var headerPickerRow: some View {
        PhotosPicker(selection: $headerPickerItem, matching: .images) {
            ZStack(alignment: .bottomTrailing) {
                // Preview the selected image or the current header URL
                Group {
                    if let headerImage = viewModel.headerImage {
                        Image(uiImage: headerImage)
                            .resizable()
                            .scaledToFill()
                    } else if let url = viewModel.community.headerImageURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            default:
                                headerPlaceholder
                            }
                        }
                    } else {
                        headerPlaceholder
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 100)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                // Edit badge
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var headerPlaceholder: some View {
        Rectangle()
            .fill(Color(.systemGray4))
            .overlay {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("Tap to set header")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
    }

    // MARK: - Avatar image picker row

    private var avatarPickerRow: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $avatarPickerItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let avatarImage = viewModel.avatarImage {
                            Image(uiImage: avatarImage)
                                .resizable()
                                .scaledToFill()
                        } else if let url = viewModel.community.avatarImageURL {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().scaledToFill()
                                default:
                                    avatarPlaceholder
                                }
                            }
                        } else {
                            avatarPlaceholder
                        }
                    }
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())

                    Image(systemName: "pencil.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .offset(x: 2, y: 2)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Community Avatar")
                    .font(.subheadline)
                Text("Tap to change")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var avatarPlaceholder: some View {
        Circle()
            .fill(Color(.systemGray4))
            .overlay {
                Image(systemName: "person.3.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CommunitySettingsView") {
    let community = RosemountCommunity(
        id: "https://rosemount.social/communities/softball-league",
        slug: "softball-league",
        name: "Springfield Softball League",
        description: "The premier softball community in Springfield.",
        avatarURL: nil,
        headerURL: nil,
        isPrivate: false,
        memberCount: 142,
        postCount: 891,
        createdAt: "2024-01-15T09:00:00.000Z",
        instanceHost: "rosemount.social",
        myRole: .admin,
        isMember: true,
        isPinned: false,
        pinnedPostIds: []
    )
    CommunitySettingsView(community: community)
        .environment(AuthManager.shared)
}
#endif
