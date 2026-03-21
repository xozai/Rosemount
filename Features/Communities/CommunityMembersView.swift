// CommunityMembersView.swift
// Rosemount
//
// Member directory with role management for a community.
// Displays all members grouped by role, supports search, infinite scroll,
// pull-to-refresh, and context-menu role/removal actions for admins.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import Observation

// RosemountCommunity  — Core/Communities/Models/RosemountCommunity.swift
// CommunityMember     — Core/Communities/Models/CommunityMember.swift
// CommunityRole       — Core/Communities/Models/RosemountCommunity.swift
// CommunityAPIClient  — Core/Communities/CommunityAPIClient.swift
// AccountCredential   — Core/Auth/AuthManager.swift
// AuthManager         — Core/Auth/AuthManager.swift
// AvatarView          — Shared/Components/AvatarView.swift

// MARK: - CommunityMembersViewModel

@Observable
@MainActor
final class CommunityMembersViewModel {

    // MARK: State

    var members: [CommunityMember] = []
    var isLoading: Bool = false
    var isLoadingMore: Bool = false
    var error: Error? = nil
    var hasMore: Bool = true
    var searchQuery: String = ""

    // MARK: Remove-confirmation alert data

    /// Set to the member pending removal to trigger a confirmation alert.
    var memberPendingRemoval: CommunityMember? = nil

    // MARK: Private

    private var slug: String = ""
    private var canManage: Bool = false
    private var page: Int = 1
    private var client: CommunityAPIClient?

    // MARK: - Setup

    /// Configures the view-model for a specific community and credential.
    /// Must be called before `refresh()`.
    func setup(slug: String, credential: AccountCredential, canManage: Bool) {
        self.slug = slug
        self.canManage = canManage
        self.client = CommunityAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Filtered members

    /// Members filtered by the current `searchQuery`.
    /// When `searchQuery` is empty all members are returned.
    var filteredMembers: [CommunityMember] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return members }
        return members.filter { member in
            let name = member.account.displayName.lowercased()
            let handle = member.account.acct.lowercased()
            return name.contains(query) || handle.contains(query)
        }
    }

    // MARK: - Members grouped by role

    /// Admins among `filteredMembers`.
    var adminMembers: [CommunityMember] {
        filteredMembers.filter { $0.role == .admin }
    }

    /// Moderators among `filteredMembers`.
    var moderatorMembers: [CommunityMember] {
        filteredMembers.filter { $0.role == .moderator }
    }

    /// Regular members among `filteredMembers`.
    var regularMembers: [CommunityMember] {
        filteredMembers.filter { $0.role == .member }
    }

    // MARK: - Refresh

    /// Resets pagination and reloads the first page of members.
    func refresh() async {
        guard let client else { return }
        guard !isLoading else { return }

        isLoading = true
        error = nil
        page = 1
        hasMore = true

        do {
            let fetched = try await client.members(slug: slug, page: 1)
            members = fetched
            hasMore = !fetched.isEmpty
            if !fetched.isEmpty { page = 2 }
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Load More

    /// Appends the next page of members (pagination).
    func loadMore() async {
        guard let client, hasMore, !isLoadingMore, !isLoading else { return }

        isLoadingMore = true

        do {
            let fetched = try await client.members(slug: slug, page: page)
            if fetched.isEmpty {
                hasMore = false
            } else {
                // Deduplicate by ID before appending.
                let existingIDs = Set(members.map(\.id))
                let fresh = fetched.filter { !existingIDs.contains($0.id) }
                members.append(contentsOf: fresh)
                hasMore = !fresh.isEmpty
                page += 1
            }
        } catch {
            // Silently ignore pagination errors; the existing list remains intact.
            self.error = error
        }

        isLoadingMore = false
    }

    // MARK: - Role Actions

    /// Promotes a member to `.moderator`.
    func promoteToModerator(_ member: CommunityMember) async {
        await updateRole(member, newRole: .moderator)
    }

    /// Demotes a moderator back to `.member`.
    func demoteToMember(_ member: CommunityMember) async {
        await updateRole(member, newRole: .member)
    }

    /// Removes a member from the community.
    /// Sets `memberPendingRemoval` to drive a confirmation alert before calling this.
    func removeMember(_ member: CommunityMember) async {
        guard let client else { return }
        do {
            try await client.removeMember(slug: slug, accountId: member.account.id)
            members.removeAll { $0.id == member.id }
        } catch {
            self.error = error
        }
        memberPendingRemoval = nil
    }

    // MARK: - Private helpers

    private func updateRole(_ member: CommunityMember, newRole: CommunityRole) async {
        guard let client else { return }
        do {
            let updated = try await client.updateMemberRole(
                slug: slug,
                accountId: member.account.id,
                role: newRole
            )
            if let index = members.firstIndex(where: { $0.id == member.id }) {
                members[index] = updated
            }
        } catch {
            self.error = error
        }
    }
}

// MARK: - CommunityMembersView

struct CommunityMembersView: View {

    // MARK: Init

    private let slug: String
    private let canManage: Bool

    init(slug: String, canManage: Bool) {
        self.slug = slug
        self.canManage = canManage
    }

    // MARK: State

    @State private var viewModel = CommunityMembersViewModel()
    @Environment(AuthManager.self) private var authManager

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.members.isEmpty {
                    loadingView
                } else if let error = viewModel.error, viewModel.members.isEmpty {
                    errorView(error)
                } else if viewModel.filteredMembers.isEmpty && !viewModel.searchQuery.isEmpty {
                    noResultsView
                } else {
                    memberList
                }
            }
            .navigationTitle("Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    memberCountBadge
                }
            }
            .searchable(
                text: $viewModel.searchQuery,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search members"
            )
            .alert("Remove Member", isPresented: Binding(
                get: { viewModel.memberPendingRemoval != nil },
                set: { if !$0 { viewModel.memberPendingRemoval = nil } }
            )) {
                Button("Remove", role: .destructive) {
                    if let pending = viewModel.memberPendingRemoval {
                        Task { await viewModel.removeMember(pending) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.memberPendingRemoval = nil
                }
            } message: {
                if let pending = viewModel.memberPendingRemoval {
                    let name = pending.account.displayName.isEmpty
                        ? pending.account.username
                        : pending.account.displayName
                    Text("Remove \(name) from this community? They will need to be re-invited to rejoin.")
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil && viewModel.memberPendingRemoval == nil },
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
            viewModel.setup(slug: slug, credential: credential, canManage: canManage)
            await viewModel.refresh()
        }
    }

    // MARK: - Member list

    private var memberList: some View {
        List {
            // Admins section
            if !viewModel.adminMembers.isEmpty {
                Section("Admin") {
                    ForEach(viewModel.adminMembers) { member in
                        memberRow(member)
                    }
                }
            }

            // Moderators section
            if !viewModel.moderatorMembers.isEmpty {
                Section("Moderators") {
                    ForEach(viewModel.moderatorMembers) { member in
                        memberRow(member)
                    }
                }
            }

            // Regular members section
            if !viewModel.regularMembers.isEmpty {
                Section("Members") {
                    ForEach(viewModel.regularMembers) { member in
                        memberRow(member)
                    }

                    // Infinite scroll trigger
                    if viewModel.hasMore {
                        paginationTrigger
                    }
                }
            }

            // Pagination spinner
            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 8)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func memberRow(_ member: CommunityMember) -> some View {
        let isOwnAccount = member.account.acct == authManager.activeAccount?.handle

        MemberRowView(
            member: member,
            canManage: canManage && !isOwnAccount,
            onRoleChange: { newRole in
                Task {
                    switch newRole {
                    case .moderator:
                        await viewModel.promoteToModerator(member)
                    case .member:
                        await viewModel.demoteToMember(member)
                    case .admin:
                        break // not offered in the UI
                    }
                }
            },
            onRemove: {
                viewModel.memberPendingRemoval = member
            }
        )
    }

    // MARK: - Pagination trigger

    private var paginationTrigger: some View {
        Color.clear
            .frame(height: 1)
            .listRowSeparator(.hidden)
            .onAppear {
                Task { await viewModel.loadMore() }
            }
    }

    // MARK: - Toolbar badge

    private var memberCountBadge: some View {
        Group {
            if !viewModel.members.isEmpty {
                Text("\(viewModel.members.count)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor, in: Capsule())
            }
        }
    }

    // MARK: - Placeholder states

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.3)
            Text("Loading members…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Couldn't load members")
                .font(.headline)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button("Try Again") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var noResultsView: some View {
        ContentUnavailableView.search(text: viewModel.searchQuery)
    }
}

// MARK: - MemberRowView

struct MemberRowView: View {

    let member: CommunityMember
    let canManage: Bool
    let onRoleChange: (CommunityRole) -> Void
    let onRemove: () -> Void

    init(
        member: CommunityMember,
        canManage: Bool,
        onRoleChange: @escaping (CommunityRole) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.member = member
        self.canManage = canManage
        self.onRoleChange = onRoleChange
        self.onRemove = onRemove
    }

    var body: some View {
        HStack(spacing: 10) {

            // Avatar
            AvatarView(
                url: member.account.avatarURL,
                size: 44,
                shape: .circle
            )

            // Name + handle + activity indicator
            VStack(alignment: .leading, spacing: 2) {
                let displayName = member.account.displayName.isEmpty
                    ? member.account.username
                    : member.account.displayName

                Text(displayName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                Text("@\(member.account.acct)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Circle()
                        .fill(member.isActive ? Color.green : Color(.systemGray3))
                        .frame(width: 6, height: 6)
                    Text(member.isActive ? "Active" : "Inactive")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 1)
            }

            Spacer(minLength: 0)

            // Role badge
            roleBadge(for: member.role)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            if canManage {
                contextMenuItems
            }
        }
    }

    // MARK: - Role badge

    private func roleBadge(for role: CommunityRole) -> some View {
        HStack(spacing: 4) {
            Image(systemName: role.systemImage)
                .font(.caption2)
            Text(role.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundStyle(roleForegroundColor(role))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(roleBackgroundColor(role), in: Capsule())
    }

    private func roleForegroundColor(_ role: CommunityRole) -> Color {
        switch role {
        case .admin:     return .white
        case .moderator: return .white
        case .member:    return Color(.label)
        }
    }

    private func roleBackgroundColor(_ role: CommunityRole) -> Color {
        switch role {
        case .admin:     return .indigo
        case .moderator: return .teal
        case .member:    return Color(.systemGray5)
        }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        // Promote: only offered when the member is a plain member
        if member.role == .member {
            Button {
                onRoleChange(.moderator)
            } label: {
                Label("Promote to Moderator", systemImage: "star.fill")
            }
        }

        // Demote: only offered when the member is a moderator
        if member.role == .moderator {
            Button {
                onRoleChange(.member)
            } label: {
                Label("Demote to Member", systemImage: "person.fill")
            }
        }

        Divider()

        Button(role: .destructive) {
            onRemove()
        } label: {
            Label("Remove from Community", systemImage: "person.fill.xmark")
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CommunityMembersView") {
    CommunityMembersView(slug: "softball-league", canManage: true)
        .environment(AuthManager.shared)
}
#endif
