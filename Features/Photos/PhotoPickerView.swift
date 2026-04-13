// PhotoPickerView.swift
// Rosemount
//
// Multi-image photo picker using PhotosUI.

import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @Binding var selectedItems: [PhotosPickerItem]
    @Binding var selectedImages: [UIImage]

    @State private var showingPicker = false
    @State private var isLoading = false

    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !selectedImages.isEmpty {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(minWidth: 0, maxWidth: .infinity)
                                .aspectRatio(1, contentMode: .fill)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .clipped()

                            Button {
                                removeImage(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                                    .padding(4)
                            }
                            .accessibilityLabel("Remove photo \(index + 1)")
                        }
                    }
                }
            }

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(String(localized: "photo.picker.loading"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            if selectedImages.count < 10 {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 10,
                    matching: .images
                ) {
                    Label("Add Photos", systemImage: "photo.badge.plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.blue)
                }
                .onChange(of: selectedItems) { _, newItems in
                    Task {
                        await loadImages(from: newItems)
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Private

    private func removeImage(at index: Int) {
        guard index < selectedImages.count else { return }
        selectedImages.remove(at: index)
        if index < selectedItems.count {
            selectedItems.remove(at: index)
        }
    }

    private func loadImages(from items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }

        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        selectedImages = images
    }
}

#Preview {
    @Previewable @State var items: [PhotosPickerItem] = []
    @Previewable @State var images: [UIImage] = []

    PhotoPickerView(selectedItems: $items, selectedImages: $images)
}
