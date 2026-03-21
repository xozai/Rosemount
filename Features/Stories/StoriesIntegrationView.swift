// Features/Stories/StoriesIntegrationView.swift
// Integrates the stories row into the home feed

import SwiftUI

struct StoriesIntegrationView: View {
    @State private var storiesViewModel = StoriesViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var viewingGroups: [StoryGroup]? = nil
    @State private var viewingGroupIndex: Int = 0
    @State private var showingComposer = false
    @State private var isViewingStories = false

    var body: some View {
        VStack(spacing: 0) {
            if storiesViewModel.isLoading && storiesViewModel.allGroups.isEmpty {
                StoriesLoadingRow()
            } else if !storiesViewModel.allGroups.isEmpty {
                StoriesRowView(
                    groups: storiesViewModel.allGroups,
                    onTap: { group in
                        let idx = storiesViewModel.allGroups.firstIndex(where: { $0.id == group.id }) ?? 0
                        viewingGroupIndex = idx
                        viewingGroups = storiesViewModel.allGroups
                        isViewingStories = true
                    },
                    onAddStory: { showingComposer = true }
                )
            }
            Divider()
        }
        .fullScreenCover(isPresented: $isViewingStories) {
            if let groups = viewingGroups {
                StoryViewerView(groups: groups, startingGroupIndex: viewingGroupIndex)
                    .environment(authManager)
            }
        }
        .sheet(isPresented: $showingComposer) {
            StoryComposerView()
                .environment(authManager)
                .onDisappear { Task { await storiesViewModel.refresh() } }
        }
        .task {
            if let account = authManager.activeAccount {
                storiesViewModel.setup(with: account)
                await storiesViewModel.refresh()
            }
        }
    }
}

struct StoriesLoadingRow: View {
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<5, id: \.self) { _ in
                    VStack(spacing: 4) {
                        Circle()
                            .fill(.gray.opacity(0.2))
                            .frame(width: 64, height: 64)
                        Rectangle()
                            .fill(.gray.opacity(0.2))
                            .frame(width: 50, height: 10)
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .redacted(reason: .placeholder)
    }
}
