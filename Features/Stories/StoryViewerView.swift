// Features/Stories/StoryViewerView.swift
// Full-screen immersive story viewer

import AVFoundation
import SwiftUI

@Observable
@MainActor
final class StoryViewerViewModel {
    var groups: [StoryGroup]
    var currentGroupIndex: Int
    var currentStoryIndex: Int = 0
    var progress: Double = 0
    var isPaused: Bool = false
    var isLoading: Bool = false
    var isDismissed: Bool = false
    private var timer: Timer?
    private var client: StoriesAPIClient?
    private let updateInterval = 0.05

    init(groups: [StoryGroup], startingAt groupIndex: Int) {
        self.groups = groups
        self.currentGroupIndex = min(groupIndex, max(0, groups.count - 1))
    }

    var currentGroup: StoryGroup { groups[currentGroupIndex] }
    var currentStory: RosemountStory { currentGroup.stories[currentStoryIndex] }
    var totalStoriesInGroup: Int { currentGroup.stories.count }

    func setup(with credential: AccountCredential) {
        client = StoriesAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func start() {
        progress = 0
        markViewed()
        scheduleTimer()
    }

    func pause() {
        isPaused = true
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        isPaused = false
        scheduleTimer()
    }

    func next() {
        timer?.invalidate()
        timer = nil
        if currentStoryIndex + 1 < currentGroup.stories.count {
            currentStoryIndex += 1
            start()
        } else if currentGroupIndex + 1 < groups.count {
            currentGroupIndex += 1
            currentStoryIndex = 0
            start()
        } else {
            isDismissed = true
        }
    }

    func previous() {
        timer?.invalidate()
        timer = nil
        if currentStoryIndex > 0 {
            currentStoryIndex -= 1
        } else if currentGroupIndex > 0 {
            currentGroupIndex -= 1
            currentStoryIndex = max(0, currentGroup.stories.count - 1)
        }
        start()
    }

    func close() {
        timer?.invalidate()
        isDismissed = true
    }

    private func scheduleTimer() {
        let duration = currentStory.duration > 0 ? currentStory.duration : 5.0
        let step = updateInterval / duration
        timer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            if self.isPaused { return }
            Task { @MainActor in
                self.progress += step
                if self.progress >= 1.0 { self.next() }
            }
        }
    }

    private func markViewed() {
        guard let client else { return }
        let storyId = currentStory.id
        Task { try? await client.viewStory(id: storyId) }
    }

    func react(emoji: String) {
        guard let client else { return }
        let storyId = currentStory.id
        Task { try? await client.reactToStory(id: storyId, emoji: emoji) }
    }
}

struct StoryViewerView: View {
    @State private var viewModel: StoryViewerViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthManager.self) private var authManager

    init(groups: [StoryGroup], startingGroupIndex: Int) {
        _viewModel = State(initialValue: StoryViewerViewModel(groups: groups, startingAt: startingGroupIndex))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Story image
            AsyncImage(url: viewModel.currentStory.mediaImageURL) { img in
                img.resizable().scaledToFit()
            } placeholder: {
                ProgressView().tint(.white)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom gradient
            LinearGradient(
                colors: [.clear, .black.opacity(0.6)],
                startPoint: .center,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                // Top: progress bars + header
                VStack(spacing: 8) {
                    HStack(spacing: 3) {
                        ForEach(0..<viewModel.totalStoriesInGroup, id: \.self) { i in
                            Capsule()
                                .fill(.white.opacity(0.35))
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    let fill: Double = i < viewModel.currentStoryIndex ? 1.0
                                        : i == viewModel.currentStoryIndex ? viewModel.progress
                                        : 0.0
                                    Capsule()
                                        .fill(.white)
                                        .frame(width: fill > 0 ? nil : 0)
                                        .animation(i == viewModel.currentStoryIndex ? .linear(duration: 0.05) : .none, value: fill)
                                }
                        }
                    }
                    .padding(.horizontal, 8)

                    HStack {
                        // Avatar + name
                        AsyncImage(url: URL(string: viewModel.currentGroup.account.avatar)) { img in
                            img.resizable().scaledToFill()
                        } placeholder: {
                            Circle().fill(.white.opacity(0.3))
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(viewModel.currentGroup.account.displayName)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                            Text(viewModel.currentStory.timeRemaining)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }

                        Spacer()

                        Button { viewModel.close() } label: {
                            Image(systemName: "xmark")
                                .font(.body.bold())
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.top, 48)

                Spacer()

                // Bottom: caption + reactions
                VStack(spacing: 12) {
                    if let caption = viewModel.currentStory.caption {
                        Text(caption)
                            .font(.callout)
                            .foregroundStyle(.white)
                            .shadow(radius: 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }

                    HStack(spacing: 16) {
                        ForEach(["❤️", "🔥", "😂", "😮", "👏"], id: \.self) { emoji in
                            Button { viewModel.react(emoji: emoji) } label: {
                                Text(emoji).font(.title2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }

            // Tap areas
            HStack {
                Color.clear.contentShape(Rectangle())
                    .frame(width: UIScreen.main.bounds.width * 0.35)
                    .onTapGesture { viewModel.previous() }
                Spacer()
                Color.clear.contentShape(Rectangle())
                    .frame(width: UIScreen.main.bounds.width * 0.35)
                    .onTapGesture { viewModel.next() }
            }
        }
        .onLongPressGesture(minimumDuration: 0.1, pressing: { pressing in
            if pressing { viewModel.pause() } else { viewModel.resume() }
        }, perform: {})
        .statusBarHidden()
        .onAppear {
            if let account = authManager.activeAccount {
                viewModel.setup(with: account)
            }
            viewModel.start()
        }
        .onChange(of: viewModel.isDismissed) { _, dismissed in
            if dismissed { dismiss() }
        }
    }
}
