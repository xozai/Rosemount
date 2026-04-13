// PhotoComposeView.swift
// Rosemount
//
// Full photo post composer sheet.

import SwiftUI
import PhotosUI

struct PhotoComposeView: View {

    @State private var viewModel = PhotoPostViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingPicker = false
    @State private var editingImageIndex: Int? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // MARK: Avatar + Horizontal Thumbnail Strip
                    HStack(alignment: .top, spacing: 12) {
                        AvatarView(
                            url: authManager.activeAccount.flatMap { URL(string: $0.avatarURL ?? "") },
                            size: 36,
                            shape: .circle
                        )

                        if viewModel.selectedImages.isEmpty {
                            Text(String(localized: "photo.compose.select_prompt"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 8)
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                        Button {
                                            editingImageIndex = index
                                        } label: {
                                            ZStack(alignment: .topTrailing) {
                                                Image(uiImage: image)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 72, height: 72)
                                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                                    .clipped()

                                                Image(systemName: "pencil.circle.fill")
                                                    .font(.system(size: 18))
                                                    .foregroundStyle(.white, .blue)
                                                    .padding(4)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("Edit photo \(index + 1)")
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // MARK: Add Photos Button
                    if viewModel.selectedImages.count < 10 {
                        Button {
                            showingPicker = true
                        } label: {
                            Label(
                                viewModel.selectedImages.isEmpty ? "Add Photos" : "Add More Photos",
                                systemImage: "photo.badge.plus"
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.blue)
                        }
                        .padding(.horizontal)
                    }

                    Divider()

                    // MARK: Caption
                    VStack(alignment: .leading, spacing: 4) {
                        TextEditor(text: $viewModel.caption)
                            .frame(minHeight: 100)
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .overlay(alignment: .topLeading) {
                                if viewModel.caption.isEmpty {
                                    Text(String(localized: "photo.compose.caption"))
                                        .font(.body)
                                        .foregroundStyle(.tertiary)
                                        .padding(.top, 8)
                                        .padding(.leading, 4)
                                        .allowsHitTesting(false)
                                }
                            }
                    }
                    .padding(.horizontal)

                    // MARK: Alt Text Fields
                    if !viewModel.selectedImages.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "photo.compose.alt_text"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            ForEach(Array(viewModel.selectedImages.enumerated()), id: \.offset) { index, image in
                                HStack(spacing: 10) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 40, height: 40)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .clipped()

                                    TextField(
                                        String(localized: "photo.compose.alt_text.field"),
                                        text: Binding(
                                            get: {
                                                viewModel.altTexts.indices.contains(index)
                                                    ? viewModel.altTexts[index]
                                                    : ""
                                            },
                                            set: { newValue in
                                                if viewModel.altTexts.indices.contains(index) {
                                                    viewModel.altTexts[index] = newValue
                                                }
                                            }
                                        ),
                                        axis: .vertical
                                    )
                                    .font(.subheadline)
                                    .lineLimit(2...4)
                                    .textFieldStyle(.roundedBorder)
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // MARK: Content Warning
                    if viewModel.hasSpoilerText {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "photo.compose.cw_label"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal)

                            TextField(String(localized: "compose.cw.placeholder"), text: $viewModel.spoilerText)
                                .textFieldStyle(.roundedBorder)
                                .padding(.horizontal)
                        }
                    }

                    // MARK: Upload Progress
                    if viewModel.isUploading {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Uploading… \(Int(viewModel.uploadProgress * 100))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            ProgressView(value: viewModel.uploadProgress)
                                .tint(.blue)
                        }
                        .padding(.horizontal)
                    }

                    // MARK: Over-limit warning
                    if viewModel.remainingCharacters < 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Text("Over limit by \(-viewModel.remainingCharacters) character\(-viewModel.remainingCharacters == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.red)
                            Spacer()
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.2), value: viewModel.remainingCharacters)
                    }

                    // MARK: Error
                    if let error = viewModel.error {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error.localizedDescription)
                                .font(.subheadline)
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.top, 16)
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(viewModel.isUploading)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        Task {
                            await viewModel.post()
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canPost)
                }
            }
            .sheet(isPresented: $showingPicker) {
                PhotoPickerView(
                    selectedItems: $selectedItems,
                    selectedImages: $viewModel.selectedImages
                )
                .presentationDetents([.medium, .large])
                .onChange(of: viewModel.selectedImages) { _, _ in
                    viewModel.syncAltTexts()
                }
            }
            .sheet(item: $editingImageIndex) { index in
                if viewModel.selectedImages.indices.contains(index) {
                    PhotoEditView(
                        image: viewModel.selectedImages[index],
                        onSave: { edited in
                            viewModel.selectedImages[index] = edited
                            editingImageIndex = nil
                        },
                        onCancel: {
                            editingImageIndex = nil
                        }
                    )
                }
            }
            .onChange(of: viewModel.didPost) { _, didPost in
                if didPost {
                    dismiss()
                }
            }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // CW Toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.hasSpoilerText.toggle()
                }
            } label: {
                Image(systemName: viewModel.hasSpoilerText ? "eye.slash.fill" : "eye.slash")
                    .font(.system(size: 18))
                    .foregroundStyle(viewModel.hasSpoilerText ? .orange : .secondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.hasSpoilerText
                ? String(localized: "photo.compose.cw_remove")
                : String(localized: "photo.compose.cw_add"))

            // Visibility Picker
            Menu {
                ForEach(MastodonVisibility.allCases, id: \.self) { vis in
                    Button {
                        viewModel.visibility = vis
                    } label: {
                        Label(vis.displayName, systemImage: vis.systemImage)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.visibility.systemImage)
                    Text(viewModel.visibility.displayName)
                        .font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color(.secondarySystemBackground))
                .clipShape(Capsule())
            }

            Spacer()

            // Character Count
            let remaining = viewModel.remainingCharacters
            Text("\(remaining)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(remaining < 0 ? .red : remaining < 50 ? .orange : .secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}

// MARK: - Int Identifiable (for sheet(item:))

extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

// MARK: - MastodonVisibility Display Helpers

extension MastodonVisibility {
    var displayName: String {
        switch self {
        case .public:   return "Public"
        case .unlisted: return "Unlisted"
        case .private:  return "Followers"
        case .direct:   return "Mentioned"
        }
    }

    var systemImage: String {
        switch self {
        case .public:   return "globe"
        case .unlisted: return "lock.open"
        case .private:  return "lock"
        case .direct:   return "envelope"
        }
    }
}

#Preview {
    PhotoComposeView()
        .environment(AuthManager.shared)
}
