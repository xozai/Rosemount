// Features/Stories/StoryComposerView.swift
// Create a new story (photo or short video)

import PhotosUI
import SwiftUI

@Observable
@MainActor
final class StoryComposerViewModel {
    var selectedImage: UIImage? = nil
    var selectedItem: PhotosPickerItem? = nil
    var caption: String = ""
    var isPosting: Bool = false
    var error: Error?
    var didPost: Bool = false
    private var client: StoriesAPIClient?

    func setup(with credential: AccountCredential) {
        client = StoriesAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func loadSelectedImage() async {
        guard let item = selectedItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            selectedImage = img
        }
    }

    func post() async {
        guard let client, let img = selectedImage else { return }
        isPosting = true
        error = nil
        do {
            guard let data = img.jpegData(compressionQuality: 0.8) else { throw E2EError.encryptionFailed }
            _ = try await client.createStory(
                mediaData: data,
                mediaType: .image,
                caption: caption.isEmpty ? nil : caption,
                backgroundColor: nil
            )
            didPost = true
        } catch {
            self.error = error
        }
        isPosting = false
    }
}

struct StoryComposerView: View {
    @State private var viewModel = StoryComposerViewModel()
    @State private var showingPicker = false
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let image = viewModel.selectedImage {
                    ZStack(alignment: .bottom) {
                        Color.black.ignoresSafeArea()

                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        VStack {
                            TextField("Add a caption...", text: $viewModel.caption)
                                .padding(12)
                                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(.white)
                                .tint(.white)
                                .padding()
                        }
                        .padding(.bottom, 20)
                    }
                    .ignoresSafeArea(edges: .bottom)
                } else {
                    VStack(spacing: 20) {
                        Spacer()
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)
                        Text("Choose a photo for your story")
                            .foregroundStyle(.secondary)
                        Button("Select Photo") { showingPicker = true }
                            .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
            }
            .navigationTitle("New Story")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.selectedImage != nil {
                        Button {
                            Task { await viewModel.post() }
                        } label: {
                            if viewModel.isPosting {
                                ProgressView().tint(.blue)
                            } else {
                                Text("Share").bold()
                            }
                        }
                        .disabled(viewModel.isPosting)
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    if viewModel.selectedImage != nil {
                        Button { showingPicker = true } label: {
                            Label("Change Photo", systemImage: "photo")
                        }
                    }
                }
            }
            .photosPicker(isPresented: $showingPicker, selection: $viewModel.selectedItem, matching: .images)
            .onChange(of: viewModel.selectedItem) { _, _ in
                Task { await viewModel.loadSelectedImage() }
            }
            .onChange(of: viewModel.didPost) { _, posted in
                if posted { dismiss() }
            }
            .task {
                if let account = authManager.activeAccount {
                    viewModel.setup(with: account)
                }
            }
        }
    }
}
