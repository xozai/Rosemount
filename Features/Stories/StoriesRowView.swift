// Features/Stories/StoriesRowView.swift
// Horizontal story bubbles row (shown at top of home feed)

import SwiftUI

struct StoriesRowView: View {
    let groups: [StoryGroup]
    let onTap: (StoryGroup) -> Void
    let onAddStory: () -> Void
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // "Add Story" button
                Button(action: onAddStory) {
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottomTrailing) {
                            if let url = authManager.activeAccount?.avatarURL {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(.gray.opacity(0.2))
                                }
                                .frame(width: 56, height: 56)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(.gray.opacity(0.2))
                                    .frame(width: 56, height: 56)
                            }
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.white, .blue)
                                .font(.title3)
                                .offset(x: 2, y: 2)
                        }
                        Text("Your Story")
                            .font(.caption2)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)

                // Other story groups
                ForEach(groups) { group in
                    StoryBubbleView(group: group) { onTap(group) }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

struct StoryBubbleView: View {
    let group: StoryGroup
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                ZStack {
                    // Ring
                    Circle()
                        .stroke(
                            group.hasUnviewed
                            ? AnyShapeStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                            : AnyShapeStyle(Color.gray.opacity(0.4)),
                            lineWidth: 2.5
                        )
                        .frame(width: 64, height: 64)

                    // Avatar
                    AsyncImage(url: URL(string: group.account.avatar)) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle()
                            .fill(.gray.opacity(0.2))
                            .overlay(
                                Text(String(group.account.displayName.prefix(1)))
                                    .font(.title3.bold())
                                    .foregroundStyle(.secondary)
                            )
                    }
                    .frame(width: 56, height: 56)
                    .clipShape(Circle())
                }

                Text(group.account.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(width: 70)
            }
        }
        .buttonStyle(.plain)
    }
}
