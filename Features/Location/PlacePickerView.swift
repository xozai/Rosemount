// Features/Location/PlacePickerView.swift
// MapKit place/POI picker to attach to a post

import MapKit
import SwiftUI

struct PlaceAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let title: String
    let subtitle: String?
    let mapItem: MKMapItem
}

@Observable
@MainActor
final class PlacePickerViewModel {
    var searchQuery: String = ""
    var searchResults: [MKMapItem] = []
    var selectedPlace: MKMapItem? = nil
    var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    var isSearching: Bool = false
    var annotations: [PlaceAnnotation] = []

    func search() async {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        defer { isSearching = false }
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = searchQuery
        req.region = region
        do {
            let response = try await MKLocalSearch(request: req).start()
            searchResults = response.mapItems
            annotations = response.mapItems.map { item in
                PlaceAnnotation(
                    coordinate: item.placemark.coordinate,
                    title: item.name ?? "Place",
                    subtitle: item.placemark.title,
                    mapItem: item
                )
            }
            if let first = response.mapItems.first {
                region = MKCoordinateRegion(
                    center: first.placemark.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
                )
            }
        } catch {
            // Ignore search errors
        }
    }

    func selectPlace(_ item: MKMapItem) {
        selectedPlace = item
    }
}

struct PlacePickerView: View {
    let onSelect: (MKMapItem) -> Void
    @State private var viewModel = PlacePickerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map(coordinateRegion: .constant(viewModel.region), annotationItems: viewModel.annotations) { pin in
                    MapAnnotation(coordinate: pin.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                            Text(pin.title)
                                .font(.caption2)
                                .padding(2)
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                .frame(height: 250)

                if viewModel.isSearching {
                    ProgressView().padding()
                } else if viewModel.searchResults.isEmpty && !viewModel.searchQuery.isEmpty {
                    Text("No places found")
                        .foregroundStyle(.secondary)
                        .padding()
                    Spacer()
                } else {
                    List(viewModel.searchResults, id: \.self) { item in
                        PlaceResultRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                viewModel.selectPlace(item)
                                onSelect(item)
                                dismiss()
                            }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Choose a Place")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $viewModel.searchQuery, prompt: "Search places")
            .onSubmit(of: .search) {
                Task { await viewModel.search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct PlaceResultRow: View {
    let item: MKMapItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.name ?? "Unknown")
                .font(.body)
            if let addr = item.placemark.title {
                Text(addr)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
}
