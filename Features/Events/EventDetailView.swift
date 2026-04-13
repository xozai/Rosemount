// Features/Events/EventDetailView.swift
// Full event detail with RSVP, map thumbnail, and attendee list

import MapKit
import SwiftUI

@Observable
@MainActor
final class EventDetailViewModel {
    var event: RosemountEvent
    var attendees: [MastodonAccount] = []
    var isLoadingAttendees: Bool = false
    var isRsvping: Bool = false
    var error: Error?
    private var client: EventAPIClient?

    init(event: RosemountEvent) {
        self.event = event
    }

    func setup(with credential: AccountCredential) {
        client = EventAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func load() async {
        guard let client else { return }
        async let updatedEvent = client.event(id: event.id)
        async let goingAttendees = client.attendees(eventId: event.id, status: .going, page: 1)
        do {
            let (e, a) = try await (updatedEvent, goingAttendees)
            event = e
            attendees = a
        } catch {
            self.error = error
        }
    }

    func rsvp(_ status: RSVPStatus) async {
        guard let client else { return }
        isRsvping = true
        do {
            event = try await client.rsvp(eventId: event.id, status: status)
        } catch {
            self.error = error
        }
        isRsvping = false
    }
}

struct EventDetailView: View {
    @State private var viewModel: EventDetailViewModel
    @Environment(AuthManager.self) private var authManager

    init(event: RosemountEvent) {
        _viewModel = State(initialValue: EventDetailViewModel(event: event))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Banner
                if let url = viewModel.event.bannerImageURL {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.gray.opacity(0.2))
                    }
                    .frame(height: 220)
                    .clipped()
                } else {
                    Rectangle()
                        .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(height: 140)
                        .overlay(
                            Image(systemName: "calendar")
                                .font(.system(size: 48))
                                .foregroundStyle(.white.opacity(0.7))
                        )
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text(viewModel.event.title)
                        .font(.title.bold())
                        .padding(.top, 8)

                    // Organizer
                    HStack(spacing: 8) {
                        AvatarView(account: viewModel.event.organizer, size: 24)
                        Text("Organized by \(viewModel.event.organizer.displayName)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Date
                    Label(viewModel.event.startDateFormatted, systemImage: "calendar")
                        .font(.subheadline)

                    // Location
                    if viewModel.event.isOnline {
                        Label("Online Event", systemImage: "video")
                            .font(.subheadline)
                        if let urlString = viewModel.event.onlineURL,
                           let onlineLink = URL(string: urlString) {
                            Link("Join Online", destination: onlineLink)
                                .font(.subheadline)
                        }
                    } else if let loc = viewModel.event.location {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(loc.name, systemImage: "mappin")
                                .font(.subheadline)
                            if let addr = loc.address {
                                Text(addr).font(.caption).foregroundStyle(.secondary)
                            }
                            if let coord = loc.coordinate {
                                Map(coordinateRegion: .constant(
                                    MKCoordinateRegion(center: coord, span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01))
                                ), annotationItems: [EventMapPin(id: "1", coordinate: coord)]) { pin in
                                    MapMarker(coordinate: pin.coordinate, tint: .blue)
                                }
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .onTapGesture {
                                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                                    mapItem.name = loc.name
                                    mapItem.openInMaps()
                                }
                            }
                        }
                    }

                    Divider()

                    // RSVP buttons
                    HStack(spacing: 12) {
                        ForEach(RSVPStatus.allCases, id: \.self) { status in
                            Button {
                                Task { await viewModel.rsvp(status) }
                            } label: {
                                Label(status.displayName, systemImage: status.systemImage)
                                    .font(.subheadline)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(viewModel.event.myRsvp == status ? Color(status.colorName).opacity(0.2) : Color.secondary.opacity(0.1))
                                    .foregroundStyle(viewModel.event.myRsvp == status ? Color(status.colorName) : .primary)
                                    .clipShape(Capsule())
                            }
                            .disabled(viewModel.isRsvping)
                        }
                    }

                    Text("\(viewModel.event.attendeeCount) going · \(viewModel.event.interestedCount) interested")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Divider()

                    // Description
                    Text(viewModel.event.description)
                        .font(.body)

                    // Attendees
                    if !viewModel.attendees.isEmpty {
                        Divider()
                        Text("Attendees")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(viewModel.attendees) { account in
                                    AvatarView(account: account, size: 44)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle(viewModel.event.title)
        .navigationBarTitleDisplayMode(.large)
        .task {
            if let account = authManager.activeAccount {
                viewModel.setup(with: account)
                await viewModel.load()
            }
        }
    }
}

private struct EventMapPin: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
}
