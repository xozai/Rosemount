// MediaLightboxView.swift
// Rosemount
//
// Full-screen image viewer with pinch-to-zoom, swipe-down-to-dismiss,
// and a page indicator for multi-image sets.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// MastodonAttachment — defined in Core/Mastodon/Models/MastodonStatus.swift

// MARK: - MediaLightboxView

/// Full-screen photo viewer presented modally over any content.
///
/// Usage:
/// ```swift
/// .sheet(isPresented: $showLightbox) {
///     MediaLightboxView(attachments: attachments, initialIndex: 0)
/// }
/// ```
struct MediaLightboxView: View {

    // MARK: - Properties

    let attachments: [MastodonAttachment]
    let initialIndex: Int

    // MARK: - State

    @Environment(\.dismiss) private var dismiss
    @State private var currentIndex: Int
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var isDragging = false

    // MARK: - Init

    init(attachments: [MastodonAttachment], initialIndex: Int = 0) {
        self.attachments = attachments
        self.initialIndex = initialIndex
        _currentIndex = State(initialValue: initialIndex)
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dark background that fades with swipe distance
            Color.black
                .opacity(1 - min(abs(offset.height) / 300, 0.6))
                .ignoresSafeArea()

            // Page view for swiping between images
            TabView(selection: $currentIndex) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    ZoomableImageView(
                        url: URL(string: attachment.url ?? ""),
                        altText: attachment.description,
                        scale: index == currentIndex ? $scale : .constant(1.0)
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .onChange(of: currentIndex) { _, _ in
                // Reset zoom when swiping to a new image
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                    offset = .zero
                }
            }

            // Swipe-down-to-dismiss gesture (only when not zoomed in)
            .gesture(
                scale <= 1.01 ? DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 {
                            offset = CGSize(
                                width: value.translation.width * 0.3,
                                height: value.translation.height
                            )
                            isDragging = true
                        }
                    }
                    .onEnded { value in
                        isDragging = false
                        if value.translation.height > 100 || value.velocity.height > 800 {
                            dismiss()
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                offset = .zero
                            }
                        }
                    }
                : nil
            )
            .offset(offset)

            // Close button
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.4))
                    .padding(16)
            }
            .accessibilityLabel("Close")

            // Page indicator dots (bottom-center)
            if attachments.count > 1 {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach(0..<attachments.count, id: \.self) { idx in
                            Circle()
                                .fill(idx == currentIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut(duration: 0.2), value: currentIndex)
                        }
                    }
                    .padding(.bottom, 32)
                }
            }

            // Alt text overlay at the bottom
            if let altText = attachments[safe: currentIndex]?.description, !altText.isEmpty {
                VStack {
                    Spacer()
                    Text(altText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                        .padding(.horizontal, 16)
                        .padding(.bottom, attachments.count > 1 ? 56 : 24)
                }
            }
        }
        .statusBarHidden()
        .animation(.easeOut(duration: 0.2), value: offset)
    }
}

// MARK: - ZoomableImageView

private struct ZoomableImageView: View {
    let url: URL?
    let altText: String?
    @Binding var scale: CGFloat

    @State private var lastScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastImageOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(scale)
                        .offset(imageOffset)
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, min(lastScale * value, 6.0))
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                    if scale < 1.1 {
                                        withAnimation(.spring(response: 0.3)) {
                                            scale = 1.0
                                            imageOffset = .zero
                                        }
                                        lastScale = 1.0
                                        lastImageOffset = .zero
                                    }
                                }
                                .simultaneously(with:
                                    DragGesture()
                                        .onChanged { value in
                                            if scale > 1.01 {
                                                imageOffset = CGSize(
                                                    width: lastImageOffset.width + value.translation.width,
                                                    height: lastImageOffset.height + value.translation.height
                                                )
                                            }
                                        }
                                        .onEnded { _ in
                                            lastImageOffset = imageOffset
                                        }
                                )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.3)) {
                                if scale > 1.1 {
                                    scale = 1.0
                                    imageOffset = .zero
                                    lastScale = 1.0
                                    lastImageOffset = .zero
                                } else {
                                    scale = 2.5
                                    lastScale = 2.5
                                }
                            }
                        }
                        .accessibilityLabel(altText ?? "Image")

                case .empty:
                    ProgressView()
                        .frame(width: geometry.size.width, height: geometry.size.height)

                case .failure:
                    Image(systemName: "photo.slash")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                @unknown default:
                    EmptyView()
                }
            }
        }
    }
}

// MARK: - Array Safe Subscript

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    MediaLightboxView(attachments: [], initialIndex: 0)
}
#endif
