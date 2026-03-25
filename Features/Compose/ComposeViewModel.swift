// ComposeViewModel.swift
// Rosemount
//
// ViewModel for the post composer. Manages draft text, visibility,
// content warnings, character counting, and posting.
//
// Swift 5.10 | iOS 17.0+

import CoreLocation
import Foundation
import MapKit
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

    // MARK: - Reply Context

    /// When non-nil, this post is a reply to the given status ID.
    var inReplyToId: String? = nil

    /// The @acct string that will be pre-pended to the reply body (e.g. "@user@mastodon.social ").
    /// Displayed as a non-editable label so it counts toward the character limit.
    var replyToMention: String = ""

    // MARK: - Draft State

    /// The main post body text.
    var content: String = ""

    /// The audience visibility setting.
    var visibility: MastodonVisibility = .public

    /// The content-warning / spoiler text. Only sent when `hasSpoilerText` is `true`.
    var spoilerText: String = ""

    /// Whether the content-warning field is shown and active.
    var hasSpoilerText: Bool = false

    // MARK: - Location

    /// Human-readable place name to display in the composer and append to the post.
    var selectedPlaceName: String? = nil

    /// Privacy-snapped coordinate; included as a structured hashtag on post.
    var selectedPlaceCoordinate: CLLocationCoordinate2D? = nil

    /// Clears the attached location tag.
    func clearLocation() {
        selectedPlaceName = nil
        selectedPlaceCoordinate = nil
    }

    /// Attaches a place picked from `PlacePickerView`.
    func attachPlace(_ mapItem: MKMapItem) {
        let name = mapItem.name ?? mapItem.placemark.locality ?? "Unknown place"
        selectedPlaceName = name
        // Grid-snap the coordinate to ~100 m for privacy.
        let snapped = CoordinateSnapper.snap(mapItem.placemark.coordinate)
        selectedPlaceCoordinate = snapped
    }

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
    /// Mastodon counts CW text, mention prefix, and body text together.
    var characterCount: Int {
        replyToMention.count + content.count + (hasSpoilerText ? spoilerText.count : 0)
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
        client = MastodonAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    /// Pre-configures the view-model as a reply to an existing status.
    ///
    /// Sets `inReplyToId`, mirrors the status's visibility (capped at `.public`),
    /// and pre-fills `replyToMention` so the mention counts toward the character limit.
    func setupReply(to status: MastodonStatus) {
        inReplyToId = status.id
        // Mirror the original post's visibility; direct replies stay direct.
        visibility = status.visibility == .direct ? .direct : status.visibility
        let acct = status.account.acct
        replyToMention = "@\(acct) "
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
            var body = replyToMention + content
            if let name = selectedPlaceName {
                if let coord = selectedPlaceCoordinate {
                    let lat = String(format: "%.4f", coord.latitude)
                    let lon = String(format: "%.4f", coord.longitude)
                    body += "\n\n📍 \(name)\n#location:\(lat),\(lon)"
                } else {
                    body += "\n\n📍 \(name)"
                }
            }
            _ = try await client.createStatus(
                content: body,
                visibility: visibility,
                inReplyToId: inReplyToId,
                spoilerText: spoiler.isEmpty ? nil : spoiler,
                mediaIds: attachments.map(\.id)
            )
            // Reset draft on success.
            content = ""
            spoilerText = ""
            hasSpoilerText = false
            attachments = []
            selectedPlaceName = nil
            selectedPlaceCoordinate = nil
            didPost = true
        } catch {
            self.error = error
        }

        isPosting = false
    }

    // MARK: - Helpers

    /// Resets all draft state without posting.
    func discardDraft() {
        inReplyToId = nil
        replyToMention = ""
        content = ""
        spoilerText = ""
        hasSpoilerText = false
        visibility = .public
        attachments = []
        selectedPlaceName = nil
        selectedPlaceCoordinate = nil
        error = nil
        didPost = false
        isPosting = false
        isUploadingMedia = false
    }
}
