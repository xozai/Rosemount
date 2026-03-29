// Features/Events/CreateEventView.swift
// Create a new event form

import MapKit
import PhotosUI
import SwiftUI

@Observable
@MainActor
final class CreateEventViewModel {
    var title: String = ""
    var description: String = ""
    var startDate: Date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    var endDate: Date? = nil
    var hasEndDate: Bool = false
    var timezone: String = TimeZone.current.identifier
    var locationName: String = ""
    var isOnline: Bool = false
    var onlineURL: String = ""
    var selectedPlace: MKMapItem? = nil
    var bannerImage: UIImage? = nil
    var bannerItem: PhotosPickerItem? = nil
    var isCreating: Bool = false
    var error: Error?
    var createdEvent: RosemountEvent? = nil
    private var communitySlug: String = ""
    private var client: EventAPIClient?

    var canCreate: Bool { title.count >= 3 && !isCreating && startDate > Date() }

    func setup(communitySlug: String, credential: AccountCredential) {
        self.communitySlug = communitySlug
        client = EventAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func loadSelectedImage() async {
        guard let item = bannerItem else { return }
        if let data = try? await item.loadTransferable(type: Data.self),
           let img = UIImage(data: data) {
            bannerImage = img
        }
    }

    func create() async {
        guard let client, canCreate else { return }
        isCreating = true
        error = nil
        do {
            var eventLocation: EventLocation? = nil
            if !isOnline {
                if let place = selectedPlace {
                    let coord = place.placemark.coordinate
                    eventLocation = EventLocation(
                        name: place.name ?? locationName,
                        address: place.placemark.title,
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                } else if !locationName.isEmpty {
                    eventLocation = EventLocation(name: locationName, address: nil, latitude: nil, longitude: nil)
                }
            }
            var bannerData: Data? = nil
            if let img = bannerImage { bannerData = img.jpegData(compressionQuality: 0.8) }
            createdEvent = try await client.createEvent(
                communitySlug: communitySlug,
                title: title,
                description: description,
                startDate: startDate,
                endDate: hasEndDate ? endDate : nil,
                timezone: timezone,
                location: eventLocation,
                isOnline: isOnline,
                onlineURL: isOnline && !onlineURL.isEmpty ? onlineURL : nil,
                bannerData: bannerData
            )
        } catch {
            self.error = error
        }
        isCreating = false
    }
}

struct CreateEventView: View {
    let communitySlug: String
    @State private var viewModel = CreateEventViewModel()
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingPlacePicker = false

    var body: some View {
        NavigationStack {
            Form {
                // Banner
                Section("Banner") {
                    PhotosPicker(selection: $viewModel.bannerItem, matching: .images) {
                        if let img = viewModel.bannerImage {
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 160)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        } else {
                            HStack {
                                Spacer()
                                Label("Add Banner Image", systemImage: "photo.badge.plus")
                                    .foregroundStyle(.blue)
                                Spacer()
                            }
                            .frame(height: 80)
                        }
                    }
                    .onChange(of: viewModel.bannerItem) { _, _ in
                        Task { await viewModel.loadSelectedImage() }
                    }
                }

                // Details
                Section("Details") {
                    TextField("Event title", text: $viewModel.title)
                    ZStack(alignment: .topLeading) {
                        if viewModel.description.isEmpty {
                            Text("Description").foregroundStyle(.tertiary).padding(.top, 8)
                        }
                        TextEditor(text: $viewModel.description)
                            .frame(minHeight: 80)
                    }
                }

                // Date & Time
                Section("Date & Time") {
                    DatePicker("Starts", selection: $viewModel.startDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    Toggle("Add end time", isOn: $viewModel.hasEndDate)
                    if viewModel.hasEndDate {
                        DatePicker("Ends", selection: Binding(
                            get: { viewModel.endDate ?? viewModel.startDate.addingTimeInterval(3600) },
                            set: { viewModel.endDate = $0 }
                        ), in: viewModel.startDate..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                // Location
                Section("Location") {
                    Toggle("Online event", isOn: $viewModel.isOnline)
                    if viewModel.isOnline {
                        TextField("URL", text: $viewModel.onlineURL)
                            .keyboardType(.URL)
                            .autocorrectionDisabled()
                    } else {
                        Button {
                            showingPlacePicker = true
                        } label: {
                            HStack {
                                Label(
                                    viewModel.selectedPlace?.name ?? (viewModel.locationName.isEmpty ? "Choose Location" : viewModel.locationName),
                                    systemImage: "mappin"
                                )
                                .foregroundStyle(viewModel.selectedPlace != nil ? .primary : .blue)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                        }
                        if viewModel.selectedPlace == nil {
                            TextField("Or type a location name", text: $viewModel.locationName)
                        }
                    }
                }

                if let error = viewModel.error {
                    Section {
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await viewModel.create()
                            if viewModel.createdEvent != nil { dismiss() }
                        }
                    }
                    .disabled(!viewModel.canCreate)
                    .overlay {
                        if viewModel.isCreating { ProgressView().scaleEffect(0.7) }
                    }
                }
            }
            .sheet(isPresented: $showingPlacePicker) {
                PlacePickerView { item in
                    viewModel.selectedPlace = item
                }
            }
            .task {
                if let account = authManager.activeAccount {
                    viewModel.setup(communitySlug: communitySlug, credential: account)
                }
            }
        }
    }
}
