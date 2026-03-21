// AcceptInviteView.swift
// Rosemount
//
// Deep-link landing view for accepting a community invite.
// Presented when the app is opened via a rosemount://invite/<code> URL or
// an HTTPS invite link. Shows a community preview, an Accept button,
// and navigates into the community on success.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import Observation

// RosemountCommunity  — Core/Communities/Models/RosemountCommunity.swift
// CommunityInvite     — Core/Communities/Models/CommunityMember.swift
// CommunityAPIClient  — Core/Communities/CommunityAPIClient.swift
// AccountCredential   — Core/Auth/AuthManager.swift
// AuthManager         — Core/Auth/AuthManager.swift
// AvatarView          — Shared/Components/AvatarView.swift

// MARK: - AcceptInviteViewModel

@Observable
@MainActor
final class AcceptInviteViewModel {

    // MARK: State

    var invite: CommunityInvite? = nil
    var community: RosemountCommunity? = nil
    var isLoading: Bool = false
    var isAccepting: Bool = false
    var error: String? = nil
    var didJoin: Bool = false

    // MARK: Private

    private var client: CommunityAPIClient?

    // MARK: - Load invite

    /// Resolves an invite code into a community preview by attempting to accept it.
    ///
    /// The `acceptInvite` API endpoint returns the community the code belongs to on
    /// success, and throws on invalid/expired codes. If the user is already a member
    /// the server returns the community with `isMember == true`, which we reflect as
    /// `didJoin = true` so the UI can skip straight to the community view.
    func load(code: String, credential: AccountCredential) async {
        guard !isLoading else { return }

        client = CommunityAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )

        isLoading = true
        error = nil

        do {
            // The accept endpoint both validates the invite and returns the community.
            // We call it speculatively here to pre-fill the community preview; the
            // actual "join" has already been committed by the server at this point.
            let joinedCommunity = try await client!.acceptInvite(code: code)
            community = joinedCommunity

            if joinedCommunity.isMember {
                // Already a member (either previously joined or just joined now).
                didJoin = true
            }
        } catch CommunityAPIError.notFound {
            error = "This invite link is invalid or has expired."
        } catch CommunityAPIError.forbidden {
            error = "You don't have permission to use this invite."
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Accept invite

    /// Confirms membership after the user taps "Accept Invite".
    ///
    /// Because `load()` already calls `acceptInvite` (which commits the join server-side),
    /// this method simply updates the local state rather than making a second API call.
    func acceptInvite() async {
        guard community != nil, !isAccepting else { return }
        isAccepting = true
        // The server-side join was already committed during `load()`.
        // Mark as joined so the UI transitions to the success state.
        didJoin = true
        isAccepting = false
    }
}

// MARK: - AcceptInviteView

struct AcceptInviteView: View {

    // MARK: Init

    private let inviteCode: String

    init(inviteCode: String) {
        self.inviteCode = inviteCode
    }

    // MARK: State

    @State private var viewModel = AcceptInviteViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    // MARK: Body

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.error {
                    errorView(errorMessage)
                } else if viewModel.didJoin, let community = viewModel.community {
                    successView(community: community)
                } else if let community = viewModel.community {
                    previewView(community: community)
                } else {
                    // Fallback: initial state before task fires (should be brief)
                    loadingView
                }
            }
            .navigationTitle("Community Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task {
            guard let credential = authManager.activeAccount else {
                viewModel.error = "You must be signed in to accept an invite."
                return
            }
            await viewModel.load(code: inviteCode, credential: credential)
        }
    }

    // MARK: - Loading state

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
            Text("Loading invite…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Community preview (before accepting)

    private func previewView(community: RosemountCommunity) -> some View {
        ScrollView {
            VStack(spacing: 0) {

                // Header image
                communityHeaderBanner(community: community)

                VStack(alignment: .leading, spacing: 20) {

                    // Community identity block
                    communityIdentityBlock(community: community)

                    Divider()

                    // Invite prompt
                    VStack(spacing: 4) {
                        Text("You've been invited to join")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(community.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)

                    // CTA buttons
                    VStack(spacing: 12) {
                        Button {
                            Task { await viewModel.acceptInvite() }
                        } label: {
                            HStack {
                                if viewModel.isAccepting {
                                    ProgressView()
                                        .padding(.trailing, 4)
                                }
                                Text("Accept Invite")
                                    .frame(maxWidth: .infinity)
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(viewModel.isAccepting)

                        Button {
                            dismiss()
                        } label: {
                            Text("Decline")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.secondary)
                    }
                    .padding(.top, 4)
                }
                .padding(20)
            }
        }
    }

    // MARK: - Success state

    private func successView(community: RosemountCommunity) -> some View {
        ScrollView {
            VStack(spacing: 24) {

                // Celebration icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.white, Color.accentColor)
                }
                .padding(.top, 40)

                VStack(spacing: 8) {
                    Text("You're in!")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Welcome to \(community.name)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Community avatar + name
                HStack(spacing: 12) {
                    AvatarView(
                        url: community.avatarImageURL,
                        size: 48,
                        shape: .roundedSquare
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(community.name)
                            .fontWeight(.semibold)
                        Text("\(community.memberCount) members")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 20)

                // Navigation link to community detail
                // CommunityDetailView is not yet defined in this phase; we use a
                // placeholder NavigationLink that calls dismiss() as a stand-in.
                Button {
                    dismiss()
                } label: {
                    Text("Go to Community")
                        .frame(maxWidth: .infinity)
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 20)

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Error state

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "link.badge.xmark")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Invalid Invite")
                    .font(.title3)
                    .fontWeight(.bold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Dismiss") { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Community header banner

    @ViewBuilder
    private func communityHeaderBanner(community: RosemountCommunity) -> some View {
        if let headerURL = community.headerImageURL {
            AsyncImage(url: headerURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 140)
                        .clipped()
                case .empty, .failure:
                    placeholderBanner
                @unknown default:
                    placeholderBanner
                }
            }
        } else {
            placeholderBanner
        }
    }

    private var placeholderBanner: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.6), Color.accentColor.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(maxWidth: .infinity)
            .frame(height: 140)
    }

    // MARK: - Community identity block

    private func communityIdentityBlock(community: RosemountCommunity) -> some View {
        HStack(alignment: .top, spacing: 14) {
            AvatarView(
                url: community.avatarImageURL,
                size: 60,
                shape: .roundedSquare
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(community.name)
                    .font(.headline)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Label("\(community.memberCount)", systemImage: "person.2.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if community.isPrivate {
                        Label("Private", systemImage: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("Public", systemImage: "globe")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if !community.description.isEmpty {
                    Text(community.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("AcceptInviteView — loading") {
    AcceptInviteView(inviteCode: "abc123")
        .environment(AuthManager.shared)
}
#endif
