// Features/Compose/DraftPickerView.swift
// Sheet for browsing and restoring saved drafts
//
// DraftPost     — Core/Offline/DraftPost.swift
// DraftsViewModel — Core/Offline/BackgroundSyncService.swift
// OfflineStore  — Core/Offline/OfflineStore.swift

import SwiftUI

struct DraftPickerView: View {

    var onSelect: (DraftPost) -> Void

    @State private var viewModel = DraftsViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.drafts.isEmpty {
                    ContentUnavailableView(
                        "No Saved Drafts",
                        systemImage: "doc.text",
                        description: Text("Posts you save while composing will appear here.")
                    )
                } else {
                    List {
                        ForEach(viewModel.drafts) { draft in
                            Button {
                                onSelect(draft)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(draft.content)
                                        .lineLimit(3)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    HStack(spacing: 6) {
                                        Text(draft.updatedAt, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text("·")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Text(draft.visibilityEnum.rawValue.capitalized)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            for i in indexSet {
                                viewModel.delete(viewModel.drafts[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !viewModel.drafts.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        EditButton()
                    }
                }
            }
            .onAppear { viewModel.load() }
        }
    }
}
