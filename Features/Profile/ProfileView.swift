// ProfileView.swift
// Rosemount
//
// User profile screen.

import SwiftUI

// MARK: - ProfileView

struct ProfileView: View {
    let accountId: String

    @State private var viewModel = ProfileViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var showGridLayout = true
    @State private var showingFollowers = false
    @State private var showingFollowing = false

    private let gridColumns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {

                // MARK: Header
                if let account = viewModel.account {
                    ProfileHeaderView(
                        account: account,
                        relationship: viewModel.relationship,
                        isOwnProfile: viewModel.isOwnProfile,
                        onFollowTap: {
                            Task { await viewModel.toggleFollow() }
                        },
                        onEditTap: {
                            // Navigate to profile edit
                        },
                        onFollowersTap: { showingFollowers = true },
                        onFollowingTap: { showingFollowing = true }
                    )
                } else if viewModel.isLoading {
                    ProfileHeaderSkeletonView()
                }

                // MARK: Layout Toggle
                HStack {
                    Spacer()
                    Picker("Layout", selection: $showGridLayout) {
                        Image(systemName: "squaregrid.3x3.fill").tag(true)
                        Image(systemName: "list.bullet").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                Divider()

                // MARK: Content
                if viewModel.isLoading && viewModel.statuses.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if viewModel.statuses.isEmpty && !viewModel.isLoading {
                    ContentUnavailableView(
                        "No Posts Yet",
                        systemImage: "photo.on.rectangle",
                        description: Text("Posts will appear here.")
                    )
                    .padding(.top, 40)
                } else if showGridLayout {
                    gridContent
                } else {
                    listContent
                }

                // MARK: Load More Indicator
                if viewModel.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
            }
        }
        .navigationTitle(viewModel.account?.displayName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !viewModel.isOwnProfile, let account = viewModel.account {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(role: .destructive) {
                            Task { await viewModel.block() }
                        } label: {
                            Label("Block @\(account.username)", systemImage: "hand.raised")
                        }

                        Button {
                            Task { await viewModel.mute() }
                        } label: {
                            Label("Mute @\(account.username)", systemImage: "speaker.slash")
                        }

                        Divider()

                        Button {
                            // Report action
                        } label: {
                            Label("Report @\(account.username)", systemImage: "flag")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(with: credential)
            await viewModel.load(accountId: accountId)
        }
        .refreshable {
            await viewModel.load(accountId: accountId)
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .sheet(isPresented: $showingFollowers) {
            NavigationStack {
                FollowersView(accountId: accountId, type: .followers)
                    .environment(authManager)
            }
        }
        .sheet(isPresented: $showingFollowing) {
            NavigationStack {
                FollowersView(accountId: accountId, type: .following)
                    .environment(authManager)
            }
        }
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        let mediaStatuses = viewModel.statuses.filter { !$0.mediaAttachments.isEmpty }

        return LazyVGrid(columns: gridColumns, spacing: 2) {
            ForEach(mediaStatuses) { status in
                if let attachment = status.mediaAttachments.first {
                    NavigationLink(value: status) {
                        GridThumbnailView(attachment: attachment)
                    }
                    .buttonStyle(.plain)
                    .onAppear {
                        if status.id == mediaStatuses.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - List Layout

    private var listContent: some View {
        LazyVStack(spacing: 0) {
            ForEach(viewModel.statuses) { status in
                PostCardView(status: status)
                    .onAppear {
                        if status.id == viewModel.statuses.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }

                Divider()
            }
        }
    }
}

// MARK: - GridThumbnailView

private struct GridThumbnailView: View {
    let attachment: MastodonAttachment

    var body: some View {
        GeometryReader { geo in
            AsyncImage(url: URL(string: attachment.previewUrl ?? attachment.url ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.width)
                        .clipped()
                case .failure:
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(.tertiary)
                        }
                case .empty:
                    Rectangle()
                        .fill(Color(.secondarySystemBackground))
                        .overlay { ProgressView().controlSize(.small) }
                @unknown default:
                    EmptyView()
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - ProfileHeaderSkeletonView

private struct ProfileHeaderSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color(.secondarySystemBackground))
                .frame(maxWidth: .infinity)
                .frame(height: 160)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Circle()
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 80, height: 80)
                        .offset(y: -32)

                    Spacer()

                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 110, height: 34)
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 140, height: 18)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 100, height: 14)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxWidth: .infinity)
                        .frame(height: 14)
                }
                .padding(.horizontal)
                .padding(.top, -20)
            }
            .padding(.bottom, 16)
        }
        .redacted(reason: .placeholder)
    }
}

// MARK: - ProfileHeaderView

struct ProfileHeaderView: View {
    let account: MastodonAccount
    let relationship: MastodonRelationship?
    let isOwnProfile: Bool
    let onFollowTap: () -> Void
    let onEditTap: () -> Void
    var onFollowersTap: (() -> Void)? = nil
    var onFollowingTap: (() -> Void)? = nil

    @State private var isBioExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // MARK: Header Image
            AsyncImage(url: URL(string: account.headerURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                        .clipped()
                case .failure, .empty:
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.blue.opacity(0.3), Color.purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                @unknown default:
                    EmptyView()
                }
            }

            // MARK: Avatar + Follow Button Row
            HStack(alignment: .bottom) {
                ZStack(alignment: .bottomTrailing) {
                    AvatarView(
                        url: URL(string: account.avatarURL ?? ""),
                        size: 80,
                        shape: .circle
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(Color(.systemBackground), lineWidth: 3)
                    }

                    if account.locked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(Color.gray)
                            .clipShape(Circle())
                            .offset(x: 4, y: 4)
                    }
                }
                .offset(y: -28)

                Spacer()

                // Follow / Edit Profile Button
                if isOwnProfile {
                    Button(action: onEditTap) {
                        Text("Edit Profile")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .overlay {
                                Capsule()
                                    .strokeBorder(.secondary.opacity(0.5), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                } else {
                    FollowButton(
                        relationship: relationship,
                        isOwnProfile: isOwnProfile,
                        onTap: onFollowTap
                    )
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal)

            // MARK: Name + Handle
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .center, spacing: 6) {
                    Text(account.displayName.isEmpty ? account.username : account.displayName)
                        .font(.system(size: 20, weight: .bold))
                        .lineLimit(1)

                    if account.bot {
                        Image(systemName: "cpu")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("@\(account.acct)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal)
            .padding(.top, -12)

            // MARK: Bio
            if let note = account.note, !note.isEmpty {
                let stripped = stripHTML(note)
                VStack(alignment: .leading, spacing: 4) {
                    Text(stripped)
                        .font(.subheadline)
                        .lineLimit(isBioExpanded ? nil : 3)
                        .fixedSize(horizontal: false, vertical: true)

                    if stripped.components(separatedBy: "\n").count > 3 || stripped.count > 200 {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isBioExpanded.toggle()
                            }
                        } label: {
                            Text(isBioExpanded ? "Show less" : "Show more")
                                .font(.caption)
                                .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            // MARK: Fields
            if let fields = account.fields, !fields.isEmpty {
                VStack(spacing: 0) {
                    ForEach(fields) { field in
                        HStack(alignment: .top, spacing: 8) {
                            Text(field.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 90, alignment: .trailing)

                            HStack(spacing: 4) {
                                if field.verifiedAt != nil {
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                                Text(stripHTML(field.value))
                                    .font(.caption)
                                    .foregroundStyle(field.verifiedAt != nil ? .green : .primary)
                                    .lineLimit(2)
                            }
                            Spacer()
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 6)

                        if field.id != fields.last?.id {
                            Divider()
                                .padding(.leading)
                        }
                    }
                }
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.top, 10)
            }

            // MARK: Stats
            HStack(spacing: 0) {
                StatButton(
                    value: account.statusesCount,
                    label: "Posts",
                    action: nil
                )

                Divider()
                    .frame(height: 28)

                StatButton(
                    value: account.followersCount,
                    label: "Followers",
                    action: onFollowersTap
                )

                Divider()
                    .frame(height: 28)

                StatButton(
                    value: account.followingCount,
                    label: "Following",
                    action: onFollowingTap
                )
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Helpers

    private func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8) else { return html }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue
        ]
        if let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil) {
            return attributed.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Fallback: naive tag stripping
        return html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - StatButton

private struct StatButton: View {
    let value: Int
    let label: String
    let action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 2) {
                Text(formatCount(value))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    NavigationStack {
        ProfileView(accountId: "1")
            .environment(AuthManager.shared)
    }
}
