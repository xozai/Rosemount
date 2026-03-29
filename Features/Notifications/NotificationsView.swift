// NotificationsView.swift
// Rosemount
//
// In-app notification centre: filter chips, paginated notification list,
// pull-to-refresh, infinite scroll, empty/error states.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// NotificationsViewModel   — defined in Features/Notifications/NotificationsViewModel.swift
// NotificationFilter       — defined in Features/Notifications/NotificationsViewModel.swift
// NotificationRowView      — defined in Features/Notifications/NotificationRowView.swift
// MastodonNotification     — defined in Core/Mastodon/MastodonAPIClient.swift
// AuthManager              — defined in Core/Auth/AuthManager.swift
// AccountCredential        — defined in Core/Auth/AuthManager.swift

// NetworkMonitor — defined in Core/Offline/NetworkMonitor.swift

// MARK: - NotificationsView

/// Root view for the in-app notification centre.
///
/// Presented as a tab or pushed onto a navigation stack from the app coordinator.
struct NotificationsView: View {

    // MARK: - State

    @State private var viewModel = NotificationsViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var networkMonitor = NetworkMonitor.shared

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                notificationContent
            }
            .navigationTitle(String(localized: "tab.notifications"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task {
                guard let credential = authManager.activeAccount else { return }
                viewModel.setup(with: credential)
                await viewModel.refresh()
            }
        }
    }

    // MARK: - Filter Bar

    /// Horizontally scrolling row of filter chips.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NotificationFilter.allCases) { filterCase in
                    FilterChip(
                        title: filterCase.title,
                        isSelected: viewModel.filter == filterCase
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            viewModel.filter = filterCase
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemBackground))
    }

    // MARK: - Main Content

    @ViewBuilder
    private var notificationContent: some View {
        if !networkMonitor.isConnected && viewModel.notifications.isEmpty {
            ContentUnavailableView(
                String(localized: "offline.title"),
                systemImage: "wifi.slash",
                description: Text(String(localized: "offline.subtitle"))
            )
        } else if viewModel.isLoading && viewModel.notifications.isEmpty {
            loadingView
        } else if let error = viewModel.error, viewModel.notifications.isEmpty {
            errorView(error)
        } else if viewModel.filteredNotifications.isEmpty {
            emptyStateView
        } else {
            notificationList
        }
    }

    // MARK: - Notification List

    private var notificationList: some View {
        List {
            ForEach(viewModel.filteredNotifications) { notification in
                NotificationRowView(notification: notification)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .onAppear {
                        // Infinite scroll: trigger loadMore when the last item appears.
                        if notification.id == viewModel.filteredNotifications.last?.id {
                            Task { await viewModel.loadMore() }
                        }
                    }
            }

            if viewModel.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView()
                        .padding(.vertical, 16)
                    Spacer()
                }
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView(String(localized: "notifications.loading"))
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: "notifications.error.load_failed"))
                .font(.headline)
            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button(String(localized: "timeline.error.retry")) {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: emptyStateIcon)
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(emptyStateTitle)
                .font(.headline)
            Text(emptyStateSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var emptyStateIcon: String {
        switch viewModel.filter {
        case .all:        return "bell.slash"
        case .mentions:   return "bubble.left.and.bubble.right"
        case .follows:    return "person.2"
        case .boosts:     return "arrow.2.squarepath"
        case .favourites: return "heart"
        }
    }

    private var emptyStateTitle: String {
        switch viewModel.filter {
        case .all:        return String(localized: "notifications.empty.all.title")
        case .mentions:   return String(localized: "notifications.empty.mentions.title")
        case .follows:    return String(localized: "notifications.empty.follows.title")
        case .boosts:     return String(localized: "notifications.empty.boosts.title")
        case .favourites: return String(localized: "notifications.empty.favourites.title")
        }
    }

    private var emptyStateSubtitle: String {
        switch viewModel.filter {
        case .all:        return String(localized: "notifications.empty.all.subtitle")
        case .mentions:   return String(localized: "notifications.empty.mentions.subtitle")
        case .follows:    return String(localized: "notifications.empty.follows.subtitle")
        case .boosts:     return String(localized: "notifications.empty.boosts.subtitle")
        case .favourites: return String(localized: "notifications.empty.favourites.subtitle")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await viewModel.markAllRead() }
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .disabled(viewModel.notifications.isEmpty)
            .accessibilityLabel(String(localized: "notifications.mark_all_read"))
        }
    }
}

// MARK: - FilterChip

/// A tappable pill button used in the horizontal filter bar.
private struct FilterChip: View {

    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? Color(.systemBackground) : Color(.label))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    isSelected
                        ? Color.accentColor
                        : Color(.secondarySystemBackground),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("NotificationsView") {
    NotificationsView()
        .environment(AuthManager.shared)
}
#endif
