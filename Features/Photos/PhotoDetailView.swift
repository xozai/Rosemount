// Features/Photos/PhotoDetailView.swift
// Full-screen photo post detail with action bar.

import SwiftUI

struct PhotoDetailView: View {
    let status: MastodonStatus
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var currentImageIndex: Int = 0
    @State private var isFavourited: Bool
    @State private var isBoosted: Bool
    @State private var favouriteCount: Int

    init(status: MastodonStatus) {
        self.status = status
        _isFavourited = State(initialValue: status.favourited ?? false)
        _isBoosted    = State(initialValue: status.reblogged ?? false)
        _favouriteCount = State(initialValue: status.favouritesCount)
    }

    private var images: [MastodonAttachment] {
        status.mediaAttachments.filter { $0.type == .image || $0.type == .gifv }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Photo carousel
                    if !images.isEmpty {
                        TabView(selection: $currentImageIndex) {
                            ForEach(Array(images.enumerated()), id: \.element.id) { index, attachment in
                                AsyncImage(url: URL(string: attachment.url)) { phase in
                                    switch phase {
                                    case .success(let img):
                                        img.resizable().scaledToFit()
                                    case .failure:
                                        Color.gray.opacity(0.2)
                                    default:
                                        Color.gray.opacity(0.1)
                                            .overlay(ProgressView())
                                    }
                                }
                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(Color.black)
                    }

                    // Author row
                    HStack(spacing: 10) {
                        AvatarView(url: URL(string: status.account.avatar), size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(status.account.displayName)
                                .font(.subheadline.bold())
                            Text("@\(status.account.acct)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    // Action bar
                    HStack(spacing: 24) {
                        Button {
                            withAnimation(.spring(response: 0.3)) {
                                isFavourited.toggle()
                                favouriteCount += isFavourited ? 1 : -1
                            }
                        } label: {
                            Label("\(favouriteCount)", systemImage: isFavourited ? "heart.fill" : "heart")
                                .foregroundStyle(isFavourited ? .red : .primary)
                        }

                        Button {
                            withAnimation(.spring(response: 0.3)) { isBoosted.toggle() }
                        } label: {
                            Image(systemName: isBoosted ? "arrow.2.squarepath" : "arrow.2.squarepath")
                                .foregroundStyle(isBoosted ? .green : .primary)
                        }

                        Spacer()

                        if images.count > 1 {
                            Text("\(currentImageIndex + 1)/\(images.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.title3)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)

                    // Caption
                    if let text = status.content, !text.isEmpty {
                        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                        if !stripped.isEmpty {
                            Text(stripped)
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }

                    // Alt text for current image
                    if let description = images[safe: currentImageIndex]?.description, !description.isEmpty {
                        Text(description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 16)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Safe subscript helper

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
