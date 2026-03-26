// AvatarView.swift
// Rosemount
//
// Reusable avatar image component with async loading, smooth fade-in,
// optional verification badge, and tap gesture support.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MARK: - AvatarShape

/// Defines the clipping shape used for an `AvatarView`.
enum AvatarShape {
    /// A perfect circle (default for most social contexts).
    case circle
    /// A rounded square with a corner radius of `size * 0.25` (common for app-style avatars).
    case roundedSquare
}

// MARK: - AvatarView

/// A self-contained avatar image view that loads a remote URL asynchronously.
///
/// Features:
/// - Smooth opacity fade-in on successful image load.
/// - Placeholder `person.circle.fill` SF Symbol when the URL is `nil` or loading.
/// - Optional verification badge (`checkmark.seal.fill`) overlaid on the bottom-trailing corner.
/// - Optional tap action closure.
/// - Two clipping shapes: `.circle` and `.roundedSquare`.
struct AvatarView: View {

    // MARK: - Properties

    let url: URL?
    let size: CGFloat
    let shape: AvatarShape
    var showBadge: Bool
    var action: (() -> Void)?

    // MARK: - Init

    /// Optional accessibility label shown to VoiceOver users.
    var accessibilityLabel: String

    init(
        url: URL?,
        size: CGFloat = 44,
        shape: AvatarShape = .circle,
        showBadge: Bool = false,
        accessibilityLabel: String = "Profile photo",
        action: (() -> Void)? = nil
    ) {
        self.url                = url
        self.size               = size
        self.shape              = shape
        self.showBadge          = showBadge
        self.accessibilityLabel = accessibilityLabel
        self.action             = action
    }

    // MARK: - Body

    var body: some View {
        Button {
            action?()
        } label: {
            avatarContent
                .overlay(alignment: .bottomTrailing) {
                    if showBadge {
                        verificationBadge
                    }
                }
        }
        .buttonStyle(.plain)
        // Disable the button interaction when there is no action, but keep it in the layout.
        .disabled(action == nil)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(action != nil ? [] : .isImage)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var avatarContent: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                placeholder

            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipped()
                    .clipShape(clipShape)
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))

            case .failure:
                placeholder

            @unknown default:
                placeholder
            }
        }
        .frame(width: size, height: size)
    }

    private var placeholder: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: size, height: size)
            .foregroundStyle(Color(.systemGray3))
            .clipShape(clipShape)
    }

    private var verificationBadge: some View {
        Image(systemName: "checkmark.seal.fill")
            .resizable()
            .frame(width: size * 0.28, height: size * 0.28)
            .foregroundStyle(.white, Color.accentColor)
            .offset(x: size * 0.04, y: size * 0.04)
    }

    // MARK: - Shape Helpers

    /// Returns the appropriate `AnyShape` for the configured `AvatarShape`.
    @ViewBuilder
    private var clipShape: some Shape {
        switch shape {
        case .circle:
            Circle()
        case .roundedSquare:
            RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Circle — loaded") {
    AvatarView(
        url: URL(string: "https://files.mastodon.social/accounts/avatars/000/000/001/original/d96d39a0abb45b92.jpg"),
        size: 60,
        shape: .circle,
        showBadge: true
    )
    .padding()
}

#Preview("Rounded Square — placeholder") {
    AvatarView(url: nil, size: 60, shape: .roundedSquare)
        .padding()
}
#endif
