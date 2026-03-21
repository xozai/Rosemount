// CreateCommunityView.swift
// Rosemount
//
// Sheet for creating a new community: name, description, privacy toggle,
// avatar / header image pickers, and live slug preview.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import PhotosUI

// CommunityAPIClient   — defined in Core/Communities/CommunityAPIClient.swift
// RosemountCommunity   — defined in Core/Communities/Models/RosemountCommunity.swift
// AuthManager          — defined in Core/Auth/AuthManager.swift
// AccountCredential    — defined in Core/Auth/AuthManager.swift

// MARK: - CreateCommunityViewModel

@Observable
@MainActor
final class CreateCommunityViewModel {

    // MARK: - Form Fields

    /// Community display name (minimum 3 characters).
    var name: String = ""

    /// Community description (minimum 10 characters).
    var description: String = ""

    /// When `true` the community is invite-only.
    var isPrivate: Bool = false

    /// User-chosen avatar image.
    var avatarImage: UIImage? = nil

    /// User-chosen header / banner image.
    var headerImage: UIImage? = nil

    // MARK: - Async State

    /// `true` while the creation request is in flight.
    var isCreating: Bool = false

    /// Non-`nil` when creation failed; used to drive an alert.
    var error: Error? = nil

    /// Non-`nil` after successful creation; observed by the view to trigger dismissal.
    var createdCommunity: RosemountCommunity? = nil

    // MARK: - Computed Properties

    /// URL-safe slug derived from `name`:
    /// lowercase, spaces → hyphens, non-alphanumeric characters stripped.
    var slug: String {
        name
            .lowercased()
            .components(separatedBy: .whitespaces)
            .joined(separator: "-")
            .filter { $0.isLetter || $0.isNumber || $0 == "-" }
    }

    /// `true` when all minimum requirements are met and no request is in flight.
    var canCreate: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && description.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10
            && !isCreating
    }

    // MARK: - Private State

    private var client: CommunityAPIClient?

    // MARK: - Setup

    /// Configures the view-model for a specific authenticated account.
    ///
    /// - Parameter credential: The active `AccountCredential`.
    func setup(with credential: AccountCredential) {
        client = CommunityAPIClient(credential: credential)
    }

    // MARK: - Create

    /// Submits the new community to the API.
    ///
    /// On success, sets `createdCommunity` (triggers the view to dismiss).
    /// On failure, stores the error so the view can display an alert.
    func create() async {
        guard let client, canCreate else { return }

        isCreating = true
        error = nil

        do {
            let community = try await client.createCommunity(
                name:        name.trimmingCharacters(in: .whitespacesAndNewlines),
                slug:        slug,
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                isPrivate:   isPrivate,
                avatarImage: avatarImage,
                headerImage: headerImage
            )
            createdCommunity = community
        } catch {
            self.error = error
        }

        isCreating = false
    }
}

// MARK: - CreateCommunityView

struct CreateCommunityView: View {

    // MARK: - State

    @State private var viewModel = CreateCommunityViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // PhotosPicker selection items.
    @State private var avatarPickerItem: PhotosPickerItem? = nil
    @State private var headerPickerItem: PhotosPickerItem? = nil

    // MARK: - Constants

    private let headerHeight: CGFloat = 120
    private let avatarSize:   CGFloat = 60

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {

                // ── Photos Section ──────────────────────────────────────────
                Section {
                    ZStack(alignment: .bottomLeading) {
                        // Header image picker (full-width).
                        headerImagePicker
                            .frame(maxWidth: .infinity)
                            .frame(height: headerHeight)

                        // Avatar image picker overlapping the header bottom-left.
                        avatarImagePicker
                            .offset(x: 16, y: avatarSize / 2)
                    }
                    .listRowInsets(EdgeInsets())
                    // Extra padding at the bottom so the avatar doesn't clip into the next section.
                    .padding(.bottom, avatarSize / 2 + 8)
                } header: {
                    Text("Photos")
                }

                // ── Details Section ─────────────────────────────────────────
                Section {
                    // Name field.
                    TextField("Community name", text: $viewModel.name)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.words)

                    // Live slug preview.
                    if !viewModel.slug.isEmpty {
                        Text("@\(viewModel.slug)@rosemount.social")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Description text editor.
                    ZStack(alignment: .topLeading) {
                        if viewModel.description.isEmpty {
                            Text("Description (minimum 10 characters)")
                                .foregroundStyle(Color(.placeholderText))
                                .font(.body)
                                .padding(.top, 8)
                                .padding(.leading, 4)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 80)
                            .scrollContentBackground(.hidden)
                    }
                } header: {
                    Text("Details")
                } footer: {
                    if viewModel.name.count > 0 && viewModel.name.count < 3 {
                        Text("Name must be at least 3 characters.")
                            .foregroundStyle(.red)
                    }
                    if viewModel.description.count > 0 && viewModel.description.count < 10 {
                        Text("Description must be at least 10 characters.")
                            .foregroundStyle(.red)
                    }
                }

                // ── Privacy Section ─────────────────────────────────────────
                Section {
                    Toggle("Private community", isOn: $viewModel.isPrivate)
                } footer: {
                    Text(
                        viewModel.isPrivate
                            ? "Only people you invite can join this community. Posts are hidden from non-members."
                            : "Anyone on the fediverse can find and join this community."
                    )
                    .foregroundStyle(.secondary)
                } header: {
                    Text("Privacy")
                }
            }
            .navigationTitle("New Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Cancel button.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                // Create button (or spinner while in flight).
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isCreating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Button("Create") {
                            Task { await viewModel.create() }
                        }
                        .fontWeight(.semibold)
                        .disabled(!viewModel.canCreate)
                    }
                }
            }
            .alert("Couldn't Create Community", isPresented: Binding(
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
        }
        // Dismiss as soon as the community is created.
        .onChange(of: viewModel.createdCommunity) { _, newValue in
            if newValue != nil { dismiss() }
        }
        // Load avatar image data when the picker selection changes.
        .onChange(of: avatarPickerItem) { _, item in
            Task { await loadImage(from: item, into: \.avatarImage) }
        }
        // Load header image data when the picker selection changes.
        .onChange(of: headerPickerItem) { _, item in
            Task { await loadImage(from: item, into: \.headerImage) }
        }
    }

    // MARK: - Header Image Picker

    private var headerImagePicker: some View {
        PhotosPicker(selection: $headerPickerItem, matching: .images) {
            ZStack {
                // Display chosen image or a placeholder gradient.
                if let headerImage = viewModel.headerImage {
                    Image(uiImage: headerImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .frame(height: headerHeight)
                        .clipped()
                } else {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: headerHeight)
                }

                // Camera icon overlay.
                VStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                    Text("Add Banner")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundStyle(.white.opacity(0.85))
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Avatar Image Picker

    private var avatarImagePicker: some View {
        PhotosPicker(selection: $avatarPickerItem, matching: .images) {
            ZStack {
                // Display chosen image or a placeholder.
                if let avatarImage = viewModel.avatarImage {
                    Image(uiImage: avatarImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: avatarSize * 0.25, style: .continuous)
                        .fill(Color(.systemGray4))
                        .frame(width: avatarSize, height: avatarSize)
                        .overlay {
                            Image(systemName: "camera.fill")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                }

                // White border to visually separate the avatar from the header.
                RoundedRectangle(cornerRadius: avatarSize * 0.25 + 2, style: .continuous)
                    .strokeBorder(.white, lineWidth: 3)
                    .frame(width: avatarSize + 4, height: avatarSize + 4)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Loads a `UIImage` from a `PhotosPickerItem` and writes it into the view-model.
    private func loadImage(
        from item: PhotosPickerItem?,
        into keyPath: ReferenceWritableKeyPath<CreateCommunityViewModel, UIImage?>
    ) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                viewModel[keyPath: keyPath] = image
            }
        } catch {
            // Non-fatal: swallow image loading errors silently.
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview {
    CreateCommunityView()
        .environment(AuthManager.shared)
}
#endif
