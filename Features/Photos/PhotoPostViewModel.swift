// PhotoPostViewModel.swift
// Rosemount
//
// ViewModel for composing a photo post.

import SwiftUI
import Observation

@Observable
@MainActor
final class PhotoPostViewModel {

    // MARK: - Published State

    var selectedImages: [UIImage] = []
    var altTexts: [String] = []
    var caption: String = ""
    var visibility: MastodonVisibility = .public
    var spoilerText: String = ""
    var hasSpoilerText: Bool = false
    var isUploading: Bool = false
    var uploadProgress: Double = 0.0
    var error: Error?
    var didPost: Bool = false

    // MARK: - Computed Properties

    var remainingCharacters: Int {
        500 - caption.count
    }

    var canPost: Bool {
        !selectedImages.isEmpty && !isUploading && remainingCharacters >= 0
    }

    // MARK: - Private State

    private var client: MastodonAPIClient?
    private var activeAccount: AccountCredential?

    // MARK: - Setup

    func setup(with credential: AccountCredential) {
        activeAccount = credential
        client = MastodonAPIClient(
            instanceURL: credential.instanceURL,
            accessToken: credential.accessToken
        )
    }

    // MARK: - Posting

    func post() async {
        guard let client, canPost else { return }

        isUploading = true
        uploadProgress = 0.0
        error = nil

        do {
            var mediaIds: [String] = []
            let total = Double(selectedImages.count)

            for (index, image) in selectedImages.enumerated() {
                let description = altTexts.indices.contains(index) ? altTexts[index] : ""
                guard let data = image.jpegData(compressionQuality: 0.85) else {
                    throw PhotoPostError.imageEncodingFailed
                }

                let attachment = try await client.uploadMedia(
                    data: data,
                    mimeType: "image/jpeg",
                    description: description.isEmpty ? nil : description
                )
                mediaIds.append(attachment.id)
                uploadProgress = Double(index + 1) / total
            }

            let finalCaption = hasSpoilerText
                ? caption
                : caption

            _ = try await client.createStatus(
                content: finalCaption,
                visibility: visibility,
                mediaIds: mediaIds,
                spoilerText: hasSpoilerText && !spoilerText.isEmpty ? spoilerText : nil
            )

            didPost = true
        } catch {
            self.error = error
        }

        isUploading = false
    }

    // MARK: - Alt Text Management

    /// Ensure altTexts array is in sync with selectedImages.
    func syncAltTexts() {
        while altTexts.count < selectedImages.count {
            altTexts.append("")
        }
        while altTexts.count > selectedImages.count {
            altTexts.removeLast()
        }
    }
}

// MARK: - Errors

enum PhotoPostError: LocalizedError {
    case imageEncodingFailed
    case noActiveAccount

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "Failed to encode one or more images."
        case .noActiveAccount:
            return "No active account found. Please sign in and try again."
        }
    }
}
