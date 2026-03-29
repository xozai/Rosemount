// Features/Stories/StoriesViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class StoriesViewModel {
    var storyGroups: [StoryGroup] = []
    var myStories: [RosemountStory] = []
    var isLoading: Bool = false
    var error: Error?
    private var client: StoriesAPIClient?
    private var credential: AccountCredential?

    func setup(with credential: AccountCredential) {
        self.credential = credential
        client = StoriesAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        error = nil
        do {
            async let groups = client.feedStories()
            async let mine = client.myStories()
            let (g, m) = try await (groups, mine)
            storyGroups = g
            myStories = m
        } catch {
            self.error = error
        }
        isLoading = false
    }

    func deleteStory(_ story: RosemountStory) async {
        guard let client else { return }
        myStories.removeAll { $0.id == story.id }
        try? await client.deleteStory(id: story.id)
    }

    var allGroups: [StoryGroup] {
        var groups: [StoryGroup] = []
        if !myStories.isEmpty, let cred = credential {
            let ownAccount = MastodonAccount(
                id: cred.id.uuidString,
                username: cred.handle,
                acct: cred.handle,
                displayName: cred.displayName ?? cred.handle,
                locked: false,
                bot: false,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                note: "",
                url: cred.actorURL?.absoluteString ?? "",
                avatar: cred.avatarURL?.absoluteString ?? "",
                avatarStatic: cred.avatarURL?.absoluteString ?? "",
                header: "",
                headerStatic: "",
                followersCount: 0,
                followingCount: 0,
                statusesCount: 0,
                emojis: [],
                fields: []
            )
            groups.append(StoryGroup(account: ownAccount, stories: myStories))
        }
        groups.append(contentsOf: storyGroups)
        return groups
    }
}
