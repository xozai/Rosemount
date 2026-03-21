// Features/Events/EventsView.swift
// Event list for a community

import SwiftUI

struct EventsView: View {
    let communitySlug: String
    @State private var viewModel = EventsViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var showingCreate = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Events")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Toggle("Upcoming", isOn: $viewModel.showUpcomingOnly)
                        .onChange(of: viewModel.showUpcomingOnly) { _, _ in
                            Task { await viewModel.refresh() }
                        }
                        .labelsHidden()
                        .toggleStyle(.button)
                }
            }
            .sheet(isPresented: $showingCreate) {
                CreateEventView(communitySlug: communitySlug)
                    .onDisappear { Task { await viewModel.refresh() } }
            }
            .refreshable { await viewModel.refresh() }
            .task {
                if let account = authManager.activeAccount {
                    viewModel.setup(communitySlug: communitySlug, credential: account)
                    await viewModel.refresh()
                }
            }
        }
    }

    private var eventList: some View {
        List {
            ForEach(viewModel.events) { event in
                NavigationLink(destination: EventDetailView(event: event)) {
                    EventRowView(event: event) { status in
                        Task { await viewModel.rsvp(event: event, status: status) }
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .onAppear {
                    if event.id == viewModel.events.last?.id {
                        Task { await viewModel.loadMore() }
                    }
                }
            }
            if viewModel.isLoadingMore {
                HStack { Spacer(); ProgressView(); Spacer() }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("No events yet")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Event Row

struct EventRowView: View {
    let event: RosemountEvent
    let onRSVP: (RSVPStatus) -> Void

    private var monthAbbrev: String {
        guard let date = event.startDateParsed else { return "" }
        let f = DateFormatter()
        f.dateFormat = "MMM"
        return f.string(from: date).uppercased()
    }

    private var dayNumber: String {
        guard let date = event.startDateParsed else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d"
        return f.string(from: date)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Date block
            VStack(spacing: 2) {
                Text(monthAbbrev)
                    .font(.caption.bold())
                    .foregroundStyle(.blue)
                Text(dayNumber)
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .frame(width: 48, height: 52)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.bold())
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Image(systemName: event.isOnline ? "video" : "mappin")
                        .font(.caption)
                    Text(event.isOnline ? "Online" : (event.location?.name ?? ""))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                Text("\(event.attendeeCount) going")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // RSVP chip
            if let rsvp = event.myRsvp {
                Label(rsvp.displayName, systemImage: rsvp.systemImage)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(rsvp.colorName).opacity(0.15))
                    .foregroundStyle(Color(rsvp.colorName))
                    .clipShape(Capsule())
            } else {
                Text("RSVP")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(Capsule().stroke(.blue, lineWidth: 1.5))
                    .foregroundStyle(.blue)
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}
