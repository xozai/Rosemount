// Features/Photos/PhotoFeedView.swift
// Pixelfed-style photo feed tab — 3-column grid with Home/Discover picker.

import SwiftUI

struct PhotoFeedView: View {
    @State private var viewModel = PhotoFeedViewModel()
    @State private var selectedPost: MastodonStatus? = nil
    @Environment(AuthManager.self) private var authManager

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    var body: some View {
        NavigationStack {
            Group {
                if !viewModel.isPixelfedAccount {
                    pixelfedRequiredView
                } else if viewModel.isLoading && viewModel.posts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.posts.isEmpty {
                    errorView(error)
                } else if viewModel.posts.isEmpty {
                    emptyView
                } else {
                    photoGrid
                }
            }
            .navigationTitle("Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Feed", selection: Binding(
                        get: { viewModel.feedType },
                        set: { newType in Task { await viewModel.switchFeed(to: newType) } }
                    )) {
                        ForEach(PhotoFeedType.allCases, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
        .task {
            guard let account = authManager.activeAccount else { return }
            viewModel.setup(with: account)
            await viewModel.refresh()
        }
        .onChange(of: authManager.activeAccount) { _, newAccount in
            guard let newAccount else { return }
            viewModel.setup(with: newAccount)
            Task { await viewModel.refresh() }
        }
        .sheet(item: $selectedPost) { post in
            PhotoDetailView(status: post)
                .environment(authManager)
        }
    }

    // MARK: - Subviews

    private var photoGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(viewModel.posts) { post in
                    if let firstImage = post.mediaAttachments.first(where: { $0.type == .image || $0.type == .gifv }) {
                        PhotoGridCell(attachment: firstImage, hasMultiple: post.mediaAttachments.count > 1)
                            .onTapGesture { selectedPost = post }
                            .onAppear {
                                if post.id == viewModel.posts.last?.id {
                                    Task { await viewModel.loadMore() }
                                }
                            }
                    }
                }
            }
            if viewModel.isLoadingMore {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }
        .refreshable { await viewModel.refresh() }
    }

    private var pixelfedRequiredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.stack")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Photo Feed")
                .font(.title2.bold())
            Text("Sign in with a Pixelfed account to access the photo feed.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Photos",
            systemImage: "photo.on.rectangle.angled",
            description: Text(viewModel.feedType == .home
                ? "Follow people to see their photos here."
                : "No trending photos right now.")
        )
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Couldn't load photos")
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Retry") { Task { await viewModel.refresh() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Grid Cell

struct PhotoGridCell: View {
    let attachment: MastodonAttachment
    let hasMultiple: Bool

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: attachment.previewUrl ?? attachment.url)) { phase in
                switch phase {
                case .success(let img):
                    img.resizable().scaledToFill()
                case .failure:
                    Color.gray.opacity(0.2)
                default:
                    Color.gray.opacity(0.1)
                }
            }
            .frame(width: geo.size.width, height: geo.size.width)
            .clipped()
            .overlay(alignment: .topTrailing) {
                if hasMultiple {
                    Image(systemName: "square.on.square")
                        .font(.caption2)
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                        .padding(4)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
