// PostCardView.swift
// Rosemount
//
// Reusable post card for timeline feeds.
// Displays a MastodonStatus with avatar, author info, content, media, polls,
// content warnings, and an action bar.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonStatus       — defined in Core/Mastodon/Models/MastodonStatus.swift
// MastodonAccount      — defined in Core/Mastodon/Models/MastodonAccount.swift
// MastodonAttachment   — defined in Core/Mastodon/Models/MastodonStatus.swift
// MastodonPoll         — defined in Core/Mastodon/Models/MastodonStatus.swift
// AvatarView           — defined in Shared/Components/AvatarView.swift

// MARK: - PostCardView

/// A full-featured timeline post card.
struct PostCardView: View {

    // MARK: - Properties

    let status: MastodonStatus
    var onTap: (() -> Void)?
    var onFavourite: (() -> Void)?
    var onBoost: (() -> Void)?
    var onReply: (() -> Void)?

    // MARK: - Init

    init(
        status: MastodonStatus,
        onTap: (() -> Void)? = nil,
        onFavourite: (() -> Void)? = nil,
        onBoost: (() -> Void)? = nil,
        onReply: (() -> Void)? = nil
    ) {
        self.status      = status
        self.onTap       = onTap
        self.onFavourite = onFavourite
        self.onBoost     = onBoost
        self.onReply     = onReply
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            // Boost header
            if let reblog = status.reblog {
                boostHeader(boostedBy: status.account, boostedContent: reblog)
            }

            // Main content row
            HStack(alignment: .top, spacing: 10) {
                // Avatar
                let displayAccount = status.reblog?.account ?? status.account
                AvatarView(
                    url: displayAccount.avatarURL,
                    size: 44,
                    shape: .circle,
                    action: nil
                )

                // Content column
                VStack(alignment: .leading, spacing: 6) {
                    // Author info
                    authorInfoRow(account: displayAccount)

                    // The actual status content (either the reblog or the original)
                    let displayStatus = status.reblog ?? status

                    // Content warning
                    if !displayStatus.spoilerText.isEmpty {
                        ContentWarningView(status: displayStatus)
                    } else {
                        statusContentView(status: displayStatus)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            .onTapGesture {
                onTap?()
            }

            Divider()
                .padding(.leading, 16 + 44 + 10) // align with content column

            // Action bar
            actionBar(status: status.reblog ?? status)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()
        }
    }

    // MARK: - Boost Header

    @ViewBuilder
    private func boostHeader(boostedBy account: MastodonAccount, boostedContent: MastodonStatus) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.2.squarepath")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(account.displayName) boosted")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    // MARK: - Author Row

    @ViewBuilder
    private func authorInfoRow(account: MastodonAccount) -> some View {
        HStack(spacing: 4) {
            Text(account.displayName.isEmpty ? account.username : account.displayName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("@\(account.acct)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text("·")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text(relativeTimestamp(from: status.createdAt))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Status Content

    @ViewBuilder
    private func statusContentView(status: MastodonStatus) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Plain text content (HTML stripped)
            if !status.content.isEmpty {
                Text(formattedContent(status.content))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Media attachments grid
            if !status.mediaAttachments.isEmpty {
                MediaAttachmentsGrid(
                    attachments: status.mediaAttachments,
                    sensitive: status.sensitive
                )
            }

            // Poll (read-only)
            if let poll = status.poll {
                PollView(poll: poll)
            }
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private func actionBar(status: MastodonStatus) -> some View {
        HStack {
            // Reply
            actionButton(
                count: status.repliesCount,
                icon: "bubble.right",
                isActive: false,
                activeColor: .accentColor
            ) {
                onReply?()
            }

            Spacer()

            // Boost
            actionButton(
                count: status.reblogsCount,
                icon: "arrow.2.squarepath",
                isActive: status.reblogged,
                activeColor: .green
            ) {
                onBoost?()
            }

            Spacer()

            // Favourite
            actionButton(
                count: status.favouritesCount,
                icon: status.favourited ? "heart.fill" : "heart",
                isActive: status.favourited,
                activeColor: .red
            ) {
                onFavourite?()
            }

            Spacer()

            // Share
            ShareLink(item: status.url.flatMap { URL(string: $0) } ?? URL(string: "https://rosemount.app")!) {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func actionButton(
        count: Int,
        icon: String,
        isActive: Bool,
        activeColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.subheadline)
                if count > 0 {
                    Text(compactCount(count))
                        .font(.subheadline)
                }
            }
            .foregroundStyle(isActive ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// Strips HTML tags and formats @mentions and #hashtags as bold runs.
    private func formattedContent(_ html: String) -> AttributedString {
        let plain = stripHTML(html)
        var attributed = AttributedString(plain)

        // Bold @mentions
        let mentionPattern = /@[\w.]+@[\w.]+|@\w+/
        let str = plain as NSString
        let range = NSRange(location: 0, length: str.length)
        let mentionRegex = try? NSRegularExpression(pattern: "@[\\w.]+@[\\w.]+|@\\w+")
        mentionRegex?.enumerateMatches(in: plain, range: range) { match, _, _ in
            guard let match else { return }
            if let swiftRange = Range(match.range, in: plain),
               let attributedRange = Range(swiftRange, in: attributed) {
                attributed[attributedRange].font = .body.bold()
            }
        }

        // Bold #hashtags
        let hashtagRegex = try? NSRegularExpression(pattern: "#\\w+")
        hashtagRegex?.enumerateMatches(in: plain, range: range) { match, _, _ in
            guard let match else { return }
            if let swiftRange = Range(match.range, in: plain),
               let attributedRange = Range(swiftRange, in: attributed) {
                attributed[attributedRange].font = .body.bold()
            }
        }

        _ = mentionPattern // suppress unused warning
        return attributed
    }

    /// Formats an engagement count compactly: 1000 → "1k", 1_000_000 → "1M".
    private func compactCount(_ n: Int) -> String {
        switch n {
        case ..<1_000:   return "\(n)"
        case ..<1_000_000: return String(format: "%.1fk", Double(n) / 1_000).replacingOccurrences(of: ".0k", with: "k")
        default:          return String(format: "%.1fM", Double(n) / 1_000_000).replacingOccurrences(of: ".0M", with: "M")
        }
    }
}

// MARK: - stripHTML

/// Strips HTML tags from a string using NSAttributedString.
/// Falls back to a simple regex strip if the attributed-string approach fails.
func stripHTML(_ html: String) -> String {
    guard !html.isEmpty else { return "" }
    // Replace <br> and <p> with newlines before stripping.
    var normalized = html
        .replacingOccurrences(of: "<br>", with: "\n")
        .replacingOccurrences(of: "<br/>", with: "\n")
        .replacingOccurrences(of: "<br />", with: "\n")
        .replacingOccurrences(of: "</p>", with: "\n")
        .replacingOccurrences(of: "<p>", with: "")

    if let data = normalized.data(using: .utf8),
       let attributed = try? NSAttributedString(
           data: data,
           options: [
               .documentType: NSAttributedString.DocumentType.html,
               .characterEncoding: NSUTF8StringEncoding
           ],
           documentAttributes: nil
       ) {
        return attributed.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Fallback: regex strip
    normalized = normalized.replacingOccurrences(
        of: "<[^>]+>",
        with: "",
        options: .regularExpression
    )
    return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - relativeTimestamp

/// Returns a compact relative timestamp string from an ISO 8601 date string.
/// Examples: "2m", "5h", "3d", "Jan 5"
func relativeTimestamp(from iso8601: String) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    var date = formatter.date(from: iso8601)
    if date == nil {
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        date = formatter.date(from: iso8601)
    }
    guard let date else { return "" }

    let seconds = Int(-date.timeIntervalSinceNow)
    switch seconds {
    case ..<60:
        return "\(max(seconds, 1))s"
    case 60..<3_600:
        return "\(seconds / 60)m"
    case 3_600..<86_400:
        return "\(seconds / 3_600)h"
    case 86_400..<604_800:
        return "\(seconds / 86_400)d"
    default:
        let cal = Calendar.current
        let components = cal.dateComponents([.month, .day], from: date)
        let month = DateFormatter().shortMonthSymbols[max((components.month ?? 1) - 1, 0)]
        let day = components.day ?? 0
        return "\(month) \(day)"
    }
}

// MARK: - ContentWarningView

/// Shows a spoiler/content-warning banner with a toggle to reveal hidden content.
struct ContentWarningView: View {

    // MastodonStatus — defined in Core/Mastodon/Models/MastodonStatus.swift
    let status: MastodonStatus

    @State private var isRevealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // CW text
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(status.spoilerText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

            // Toggle button
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRevealed.toggle()
                }
            } label: {
                Text(isRevealed ? "Show less" : "Show more")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.accentColor)

            // Revealed content
            if isRevealed {
                VStack(alignment: .leading, spacing: 8) {
                    if !status.content.isEmpty {
                        Text(stripHTML(status.content))
                            .font(.body)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !status.mediaAttachments.isEmpty {
                        MediaAttachmentsGrid(
                            attachments: status.mediaAttachments,
                            sensitive: status.sensitive
                        )
                    }
                    if let poll = status.poll {
                        PollView(poll: poll)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - MediaAttachmentsGrid

/// Displays 1–4 media attachments in an adaptive grid.
struct MediaAttachmentsGrid: View {

    // MastodonAttachment — defined in Core/Mastodon/Models/MastodonStatus.swift
    let attachments: [MastodonAttachment]
    let sensitive: Bool

    @State private var revealSensitive: Bool = false

    private var columns: [GridItem] {
        let count = min(attachments.count, 2)
        return Array(repeating: GridItem(.flexible(), spacing: 4), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if sensitive && !revealSensitive {
                sensitiveOverlay
            } else {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(attachments.prefix(4), id: \.id) { attachment in
                        attachmentCell(attachment)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private func attachmentCell(_ attachment: MastodonAttachment) -> some View {
        let imageURL = URL(string: attachment.previewUrl ?? attachment.url ?? "")
        AsyncImage(url: imageURL) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(minHeight: 100, maxHeight: 200)
                    .clipped()
            case .empty, .failure:
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(height: 120)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            @unknown default:
                EmptyView()
            }
        }
    }

    private var sensitiveOverlay: some View {
        Button {
            revealSensitive = true
        } label: {
            ZStack {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(spacing: 6) {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                    Text("Sensitive content — tap to reveal")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PollView

/// Read-only poll display showing options, vote bars, and counts.
struct PollView: View {

    // MastodonPoll — defined in Core/Mastodon/Models/MastodonStatus.swift
    let poll: MastodonPoll

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(poll.options.indices, id: \.self) { index in
                let option = poll.options[index]
                pollOptionRow(option: option, totalVotes: poll.votesCount)
            }

            HStack(spacing: 4) {
                Text("\(poll.votesCount) votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let expiresAt = poll.expiresAt {
                    Text("·")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(pollExpiryLabel(from: expiresAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    private func pollOptionRow(option: MastodonPollOption, totalVotes: Int) -> some View {
        let fraction: Double = totalVotes > 0
            ? Double(option.votesCount ?? 0) / Double(totalVotes)
            : 0

        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(option.title)
                    .font(.subheadline)
                Spacer()
                Text("\(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.systemGray5))
                        .frame(height: 6)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.8))
                        .frame(width: geo.size.width * fraction, height: 6)
                }
            }
            .frame(height: 6)
        }
    }

    private func pollExpiryLabel(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var date = formatter.date(from: iso8601)
        if date == nil {
            formatter.formatOptions = [.withInternetDateTime]
            date = formatter.date(from: iso8601)
        }
        guard let date else { return "Closed" }
        if date < Date() { return "Closed" }
        let seconds = Int(date.timeIntervalSinceNow)
        switch seconds {
        case ..<3_600:   return "Ends in \(seconds / 60)m"
        case ..<86_400:  return "Ends in \(seconds / 3_600)h"
        default:         return "Ends in \(seconds / 86_400)d"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("PostCardView — placeholder") {
    ScrollView {
        Text("PostCardView preview requires MastodonStatus sample data.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding()
    }
}
#endif
