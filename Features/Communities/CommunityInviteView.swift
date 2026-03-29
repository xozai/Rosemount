// CommunityInviteView.swift
// Rosemount
//
// Invite management and QR code sharing for a community.
// Allows moderators/admins to create, view, and revoke invite links.
// QR codes are generated via CoreImage — no external dependencies.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Observation

// CommunityInvite     — Core/Communities/Models/CommunityMember.swift
// CommunityAPIClient  — Core/Communities/CommunityAPIClient.swift
// AccountCredential   — Core/Auth/AuthManager.swift
// AuthManager         — Core/Auth/AuthManager.swift

// MARK: - InviteExpiry

/// Expiry presets offered when creating a new invite link.
enum InviteExpiry: CaseIterable, Identifiable {
    case never
    case oneDay
    case oneWeek
    case oneMonth

    var id: Self { self }

    /// `TimeInterval` in seconds to send to the API, or `nil` for no expiry.
    var seconds: TimeInterval? {
        switch self {
        case .never:    return nil
        case .oneDay:   return 86_400
        case .oneWeek:  return 604_800
        case .oneMonth: return 2_592_000
        }
    }

    var displayName: String {
        switch self {
        case .never:    return "Never"
        case .oneDay:   return "1 day"
        case .oneWeek:  return "1 week"
        case .oneMonth: return "1 month"
        }
    }
}

// MARK: - CommunityInviteViewModel

@Observable
@MainActor
final class CommunityInviteViewModel {

    // MARK: State

    var invites: [CommunityInvite] = []
    var isLoading: Bool = false
    var error: Error? = nil

    // Create-invite form state
    var newInviteMaxUses: Int? = nil          // nil = unlimited
    var newInviteExpiry: InviteExpiry = .never
    var isCreating: Bool = false

    // MARK: Private

    private var slug: String = ""
    private var client: CommunityAPIClient?

    // MARK: - Setup

    /// Configures the view-model. Must be called before any async operations.
    func setup(slug: String, credential: AccountCredential) {
        self.slug = slug
        self.client = CommunityAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Load invites

    func loadInvites() async {
        guard let client else { return }
        isLoading = true
        error = nil

        do {
            invites = try await client.invites(slug: slug)
        } catch {
            self.error = error
        }

        isLoading = false
    }

    // MARK: - Create invite

    func createInvite() async {
        guard let client, !isCreating else { return }
        isCreating = true
        error = nil

        do {
            let invite = try await client.createInvite(
                slug: slug,
                maxUses: newInviteMaxUses,
                expiresIn: newInviteExpiry.seconds
            )
            // Prepend so the newest invite appears at the top.
            invites.insert(invite, at: 0)
        } catch {
            self.error = error
        }

        isCreating = false
    }

    // MARK: - Delete invite

    func deleteInvite(_ invite: CommunityInvite) async {
        guard let client else { return }
        do {
            try await client.deleteInvite(slug: slug, inviteId: invite.id)
            invites.removeAll { $0.id == invite.id }
        } catch {
            self.error = error
        }
    }
}

// MARK: - CommunityInviteView

struct CommunityInviteView: View {

    // MARK: Init

    private let slug: String

    init(slug: String) {
        self.slug = slug
    }

    // MARK: State

    @State private var viewModel = CommunityInviteViewModel()
    @State private var selectedInvite: CommunityInvite? = nil
    @Environment(AuthManager.self) private var authManager

    // Max-uses options offered in the picker.
    private let maxUsesOptions: [(label: String, value: Int?)] = [
        ("Unlimited", nil),
        ("1 use",     1),
        ("5 uses",    5),
        ("10 uses",   10),
        ("25 uses",   25)
    ]

    // MARK: Body

    var body: some View {
        NavigationStack {
            List {

                // MARK: Create invite section
                Section("Create Invite") {
                    // Max uses picker
                    Picker("Max uses", selection: $viewModel.newInviteMaxUses) {
                        ForEach(maxUsesOptions, id: \.label) { option in
                            Text(option.label)
                                .tag(option.value)
                        }
                    }

                    // Expiry picker
                    Picker("Expires", selection: $viewModel.newInviteExpiry) {
                        ForEach(InviteExpiry.allCases) { expiry in
                            Text(expiry.displayName)
                                .tag(expiry)
                        }
                    }

                    // Generate button
                    Button {
                        Task { await viewModel.createInvite() }
                    } label: {
                        HStack {
                            if viewModel.isCreating {
                                ProgressView()
                                    .padding(.trailing, 4)
                            }
                            Text("Generate Invite Link")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(viewModel.isCreating)
                    .tint(.accentColor)
                    .listRowBackground(Color.accentColor.opacity(0.1))
                }

                // MARK: Active invites section
                Section {
                    if viewModel.isLoading && viewModel.invites.isEmpty {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.vertical, 8)
                            Spacer()
                        }
                    } else if viewModel.invites.isEmpty {
                        Text("No active invites")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(viewModel.invites) { invite in
                            InviteRowView(invite: invite) {
                                selectedInvite = invite
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await viewModel.deleteInvite(invite) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                } header: {
                    Text("Active Invites")
                } footer: {
                    if !viewModel.invites.isEmpty {
                        Text("Swipe left to delete an invite.")
                            .font(.caption)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Invite Members")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable {
                await viewModel.loadInvites()
            }
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
            .sheet(item: $selectedInvite) { invite in
                QRCodeInviteSheet(invite: invite)
            }
        }
        .task {
            guard let credential = authManager.activeAccount else { return }
            viewModel.setup(slug: slug, credential: credential)
            await viewModel.loadInvites()
        }
    }
}

// MARK: - InviteRowView

struct InviteRowView: View {

    let invite: CommunityInvite
    let onQRTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {

            // Top row: code + badges
            HStack {
                Text(invite.code)
                    .font(.body.monospaced())
                    .fontWeight(.semibold)

                Spacer()

                if invite.isExpired {
                    statusBadge("Expired", color: .red)
                } else if invite.isFull {
                    statusBadge("Full", color: .orange)
                } else {
                    statusBadge("Active", color: .green)
                }
            }

            // Middle row: uses + expiry
            HStack(spacing: 12) {
                Label(usesLabel, systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let expiryLabel {
                    Label(expiryLabel, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Bottom row: QR button + share button
            HStack(spacing: 12) {
                Button {
                    onQRTap()
                } label: {
                    Label("QR Code", systemImage: "qrcode")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                if let url = URL(string: invite.inviteURL) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Helpers

    private var usesLabel: String {
        if let maxUses = invite.maxUses {
            return "\(invite.useCount) / \(maxUses) uses"
        }
        return "\(invite.useCount) use\(invite.useCount == 1 ? "" : "s") (unlimited)"
    }

    private var expiryLabel: String? {
        guard let expiresAtString = invite.expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: expiresAtString)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: expiresAtString)
        }
        guard let date else { return "Expires: unknown" }
        if date < Date() { return "Expired" }

        let relFormatter = RelativeDateTimeFormatter()
        relFormatter.unitsStyle = .abbreviated
        return "Expires \(relFormatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func statusBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color, in: Capsule())
    }
}

// MARK: - QRCodeInviteSheet

struct QRCodeInviteSheet: View {

    let invite: CommunityInvite

    @Environment(\.dismiss) private var dismiss
    @State private var qrImage: UIImage? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {

                    // QR code image
                    if let qrImage {
                        Image(uiImage: qrImage)
                            .resizable()
                            .interpolation(.none)       // keep pixels crisp at any size
                            .scaledToFit()
                            .frame(width: 260, height: 260)
                            .padding(16)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color(.systemGray5))
                            .frame(width: 260, height: 260)
                            .overlay {
                                ProgressView()
                            }
                    }

                    // Invite URL (selectable, monospaced)
                    Text(invite.inviteURL)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                        .padding(.horizontal, 16)

                    // Action buttons
                    VStack(spacing: 12) {
                        if let url = URL(string: invite.inviteURL) {
                            ShareLink(item: url) {
                                Label("Share Invite Link", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                        }

                        Button {
                            UIPasteboard.general.string = invite.inviteURL
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.secondary)
                    }
                    .padding(.horizontal, 24)
                }
                .padding(.vertical, 32)
            }
            .navigationTitle("Invite QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            qrImage = generateQRCode(from: invite.inviteURL)
        }
    }

    // MARK: - QR code generation

    /// Generates a 300×300 UIImage QR code from the given string using CoreImage.
    ///
    /// - Parameter string: The string to encode (typically an invite URL).
    /// - Returns: A `UIImage` with crisp pixel-doubled rendering, or `nil` on failure.
    func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .utf8),
              let filter = CIFilter(name: "CIQRCodeGenerator") else {
            return nil
        }

        filter.setValue(data, forKey: "inputMessage")
        // Error correction level H (30%) gives the best scannability.
        filter.setValue("H", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }

        // Scale the small raw CIImage to 300×300 points for crisp rendering.
        let targetSize = CGSize(width: 300, height: 300)
        let scaleX = targetSize.width  / ciImage.extent.width
        let scaleY = targetSize.height / ciImage.extent.height
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("CommunityInviteView") {
    CommunityInviteView(slug: "softball-league")
        .environment(AuthManager.shared)
}
#endif
