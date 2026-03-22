// ComposeViewModel.swift
// Rosemount
//
// ViewModel for the post composer. Manages draft text, visibility,
// content warnings, character counting, and posting.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Observation
import PhotosUI
import SwiftUI

// MastodonAPIClient  — defined in Core/Mastodon/MastodonAPIClient.swift
// MastodonVisibility — defined in Core/Mastodon/Models/MastodonStatus.swift
// AccountCredential  — defined in Core/Auth/AuthManager.swift

// MARK: - ComposeViewModel

@Observable
@MainActor
final class ComposeViewModel {

    // MARK: - Mastodon Character Limit

    private static let characterLimit = 500

    // MARK: - Draft State

    /// The main post body text.
    var content: String = ""

    /// The audience visibility setting.
    var visibility: MastodonVisibility = .public

    /// The content-warning / spoiler text. Only sent when `hasSpoilerText` is `true`.
    var spoilerText: String = ""

    /// Whether the content-warning field is shown and active.
    var hasSpoilerText: Bool = false

    // MARK: - Media Attachments

    /// Uploaded media attachments to include in the post.
    var attachments: [MastodonAttachment] = []

    /// `true` while a media upload is in flight.
    var isUploadingMedia: Bool = false

    // MARK: - Posting State

    /// `true` while the network request is in flight.
    var isPosting: Bool = false

    /// Non-`nil` when posting failed; used to drive an alert.
    var error: Error? = nil

    /// Becomes `true` after a successful post; the view observes this to dismiss itself.
    var didPost: Bool = false

    // MARK: - Computed Properties

    /// Total characters that count toward the limit.
    /// Mastodon counts CW text and body text together.
    var characterCount: Int {
        content.count + (hasSpoilerText ? spoilerText.count : 0)
    }

    /// Characters remaining before hitting the server limit.
    var remainingCharacters: Int {
        Self.characterLimit - characterCount
    }

    /// `true` when the draft has content or attachments, is within the limit, and is not posting.
    var canPost: Bool {
        let hasContent = !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasContent || !attachments.isEmpty)
            && remainingCharacters >= 0
            && !isPosting
            && !isUploadingMedia
    }

    // MARK: - Private State

    private var client: MastodonAPIClient? = nil

    // MARK: - Setup

    /// Configures the view-model for a specific authenticated account.
    ///
    /// - Parameter credential: The active `AccountCredential`.
    ///   Defined in `Core/Auth/AuthManager.swift`.
    func setup(with credential: AccountCredential) {
        // MastodonAPIClient — defined in Core/Mastodon/MastodonAPIClient.swift
        client = MastodonAPIClient(credential: credential)
    }

    // MARK: - Media Upload

    /// Uploads a photo selected by the user and appends it to `attachments`.
    ///
    /// - Parameters:
    ///   - item: The `PhotosPickerItem` selected in the UI.
    ///   - altText: Optional accessibility description for the image.
    func attachPhoto(_ item: PhotosPickerItem, altText: String? = nil) async {
        guard let client else { return }
        isUploadingMedia = true
        defer { isUploadingMedia = false }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { return }
            let attachment = try await client.uploadMedia(
                data: data,
                mimeType: "image/jpeg",
                description: altText
            )
            attachments.append(attachment)
        } catch {
            self.error = error
        }
    }

    /// Removes an attachment from the draft.
    func removeAttachment(id: String) {
        attachments.removeAll { $0.id == id }
    }

    // MARK: - Post

    /// Submits the composed post to the Mastodon API.
    ///
    /// On success, sets `didPost = true` (triggers view dismissal).
    /// On failure, stores the error in `self.error`.
    func post() async {
        guard let client, canPost else { return }

        isPosting = true
        error = nil

        let spoiler = hasSpoilerText ? spoilerText.trimmingCharacters(in: .whitespacesAndNewlines) : ""

        do {
            _ = try await client.createStatus(
                content: content,
                visibility: visibility,
                spoilerText: spoiler.isEmpty ? nil : spoiler,
                mediaIds: attachments.map(\.id)
            )
            // Reset draft on success.
            content = ""
            spoilerText = ""
            hasSpoilerText = false
            attachments = []
            didPost = true
        } catch {
            self.error = error
        }

        isPosting = false
    }

    // MARK: - Helpers

    /// Resets all draft state without posting.
    func discardDraft() {
        content = ""
        spoilerText = ""
        hasSpoilerText = false
        visibility = .public
        attachments = []
        error = nil
        didPost = false
        isPosting = false
        isUploadingMedia = false
    }
}
