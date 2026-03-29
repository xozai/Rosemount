// Features/Events/GlobalEventsView.swift
// Standalone Events tab — not scoped to any community.

import SwiftUI

struct GlobalEventsView: View {
    @State private var viewModel = GlobalEventsViewModel()
    @State private var showingCreate = false
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.events.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = viewModel.error, viewModel.events.isEmpty {
                    errorView(error)
                } else if viewModel.events.isEmpty {
                    emptyState
                } else {
                    eventList
                }
            }
            .navigationTitle("Events")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .safeAreaInset(edge: .top) {
                filterPicker
                    .background(.bar)
            }
            .refreshable { await viewModel.refresh() }
            .sheet(isPresented: $showingCreate) {
                CreateEventView(communitySlug: "")
                    .environment(authManager)
                    .onDisappear { Task { await viewModel.refresh() } }
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
    }

    // MARK: - Subviews

    private var filterPicker: some View {
        Picker("Filter", selection: Binding(
            get: { viewModel.filter },
            set: { newVal in Task { await viewModel.switchFilter(to: newVal) } }
        )) {
            ForEach(GlobalEventFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var eventList: some View {
        List {
            ForEach(viewModel.events) { event in
                NavigationLink(destination: EventDetailView(event: event).environment(authManager)) {
                    EventRowView(event: event) { status in
                        Task { await viewModel.rsvp(event, status: status) }
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
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text(viewModel.filter == .mine ? "No events you've RSVP'd to" : "No \(viewModel.filter.rawValue.lowercased()) events")
                .font(.title3)
                .foregroundStyle(.secondary)
            Button("Create an Event") { showingCreate = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: Error) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Couldn't load events")
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
