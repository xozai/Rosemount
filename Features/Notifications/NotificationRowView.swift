// NotificationRowView.swift
// Rosemount
//
// Displays a single MastodonNotification in the notification centre list.
// Shows a type-appropriate icon, the actor's avatar, an action description,
// a relative timestamp, and an optional status preview.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonNotification     — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonNotificationType — defined in Core/Mastodon/MastodonAPIClient.swift
// AvatarView               — defined in Shared/Components/AvatarView.swift
// relativeTimestamp        — defined in Shared/Components/PostCardView.swift
// stripHTML                — defined in Shared/Components/PostCardView.swift

// MARK: - NotificationRowView

/// A list row that represents one `MastodonNotification`.
///
/// Tapping the row navigates to the related status (when present) or to the
/// actor's profile. The avatar always links to the actor's profile.
struct NotificationRowView: View {

    // MARK: - Properties

    let notification: MastodonNotification

    // MARK: - Init

    init(notification: MastodonNotification) {
        self.notification = notification
    }

    // MARK: - Body

    var body: some View {
        NavigationLink(value: navigationDestination) {
            rowContent
        }
        .buttonStyle(.plain)
        // Make the entire row tappable, not just the text.
        .contentShape(Rectangle())
    }

    // MARK: - Row Content

    private var rowContent: some View {
        HStack(alignment: .top, spacing: 12) {

            // Left column: type icon
            notificationIcon
                .frame(width: 24)
                .padding(.top, 2)

            // Avatar (links to profile)
            NavigationLink(value: NavigationDestination.profile(accountId: notification.account.id)) {
                AvatarView(
                    url: notification.account.avatarURL,
                    size: 44,
                    shape: .circle
                )
            }
            .buttonStyle(.plain)

            // Right column: description + optional status preview
            VStack(alignment: .leading, spacing: 4) {
                // Actor name + action label
                actionHeadline

                // Relative timestamp
                Text(relativeTimestamp(from: notification.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Status content preview (if this notification has an associated status)
                if let status = notification.status {
                    Text(stripHTML(status.displayStatus.content))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Action Headline

    /// "[Actor display name] [action description]" — bold name, regular action.
    private var actionHeadline: some View {
        Group {
            Text(actorName)
                .fontWeight(.semibold) +
            Text(" ") +
            Text(actionDescription)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .lineLimit(2)
    }

    private var actorName: String {
        let name = notification.account.displayName
        return name.isEmpty ? notification.account.username : name
    }

    private var actionDescription: String {
        switch notification.type {
        case .mention:       return "mentioned you"
        case .status:        return "posted"
        case .reblog:        return "boosted your post"
        case .follow:        return "followed you"
        case .followRequest: return "requested to follow you"
        case .favourite:     return "liked your post"
        case .poll:          return "A poll you voted in has ended"
        case .update:        return "edited a post"
        }
    }

    // MARK: - Notification Icon

    private var notificationIcon: some View {
        Image(systemName: iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iconColor)
    }

    private var iconName: String {
        switch notification.type {
        case .mention:       return "bubble.left.fill"
        case .status:        return "bell.fill"
        case .reblog:        return "arrow.2.squarepath"
        case .follow:        return "person.fill.badge.plus"
        case .followRequest: return "person.fill.questionmark"
        case .favourite:     return "heart.fill"
        case .poll:          return "chart.bar.fill"
        case .update:        return "pencil"
        }
    }

    private var iconColor: Color {
        switch notification.type {
        case .mention:       return .blue
        case .status:        return .blue
        case .reblog:        return .green
        case .follow:        return .purple
        case .followRequest: return .orange
        case .favourite:     return .red
        case .poll:          return .gray
        case .update:        return .gray
        }
    }

    // MARK: - Navigation Destination

    /// The primary navigation destination when the row is tapped.
    private var navigationDestination: NavigationDestination {
        if let status = notification.status {
            return .status(statusId: status.displayStatus.id)
        }
        return .profile(accountId: notification.account.id)
    }
}

// MARK: - NavigationDestination

/// Typed navigation values used with `NavigationStack`.
///
/// This enum covers the destinations reachable from `NotificationRowView`.
/// It must conform to `Hashable` for use as a `NavigationLink` value.
/// Extend this in the app coordinator to handle additional routes.
enum NavigationDestination: Hashable {
    case profile(accountId: String)
    case status(statusId: String)
    case conversation(conversationId: String)
}

// MARK: - Preview

#if DEBUG
#Preview("NotificationRowView — mention") {
    NavigationStack {
        List {
            // Previewing with placeholder data; real data requires MastodonNotification sample.
            Text("NotificationRowView preview requires MastodonNotification sample data.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding()
        }
        .listStyle(.plain)
        .navigationTitle("Notifications")
    }
}
#endif
