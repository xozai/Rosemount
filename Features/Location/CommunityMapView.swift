// Features/Location/CommunityMapView.swift
// Map showing community members' shared locations

import MapKit
import SwiftUI

@Observable
@MainActor
final class CommunityMapViewModel {
    var locationShares: [LocationShare] = []
    var isLoading: Bool = false
    var error: Error?
    private var client: LocationSharingAPIClient?
    private var communityId: String = ""
    private var pollingTask: Task<Void, Never>?

    func setup(communityId: String, credential: AccountCredential) {
        self.communityId = communityId
        client = LocationSharingAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func refresh() async {
        guard let client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            locationShares = try await client.communityLocations(communityId: communityId)
        } catch {
            self.error = error
        }
    }

    func startPolling() {
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                if Task.isCancelled { break }
                await refresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }
}

struct CommunityMapView: View {
    let communityId: String
    @State private var viewModel = CommunityMapViewModel()
    @Environment(AuthManager.self) private var authManager
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
    )
    @State private var selectedShare: LocationShare? = nil

    var body: some View {
        ZStack {
            Map(coordinateRegion: $region, annotationItems: viewModel.locationShares) { share in
                MapAnnotation(coordinate: share.coordinate) {
                    Button { selectedShare = share } label: {
                        ZStack {
                            Circle()
                                .fill(.white)
                                .frame(width: 40, height: 40)
                                .shadow(radius: 2)
                            if let urlStr = share.avatarURL, let url = URL(string: urlStr) {
                                AsyncImage(url: url) { img in
                                    img.resizable().scaledToFill()
                                } placeholder: {
                                    Circle().fill(.gray.opacity(0.3))
                                }
                                .frame(width: 36, height: 36)
                                .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(.blue.opacity(0.3))
                                    .frame(width: 36, height: 36)
                                    .overlay(
                                        Text(String(share.displayName.prefix(1)))
                                            .font(.caption.bold())
                                            .foregroundStyle(.blue)
                                    )
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .ignoresSafeArea(edges: .bottom)

            if viewModel.locationShares.isEmpty && !viewModel.isLoading {
                VStack {
                    Spacer()
                    Text("No one is sharing their location right now.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding()
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 60)
                }
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: viewModel.isLoading ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                            .padding(12)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .disabled(viewModel.isLoading)
                    .padding()
                }
            }
        }
        .navigationTitle("Community Map")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedShare) { share in
            MemberLocationCard(share: share)
                .presentationDetents([.height(200)])
        }
        .task {
            if let account = authManager.activeAccount {
                viewModel.setup(communityId: communityId, credential: account)
                await viewModel.refresh()
                viewModel.startPolling()
            }
        }
        .onDisappear { viewModel.stopPolling() }
    }
}

struct MemberLocationCard: View {
    let share: LocationShare
    @Environment(\.dismiss) private var dismiss

    private var sharedSince: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        // Parse sharedAt
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: share.sharedAt) {
            return "Sharing since " + f.localizedString(for: date, relativeTo: Date())
        }
        return "Recently sharing"
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 12) {
                if let urlStr = share.avatarURL, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Circle().fill(.gray.opacity(0.3))
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(Circle())
                } else {
                    Circle()
                        .fill(.blue.opacity(0.2))
                        .frame(width: 52, height: 52)
                        .overlay(
                            Text(String(share.displayName.prefix(1)))
                                .font(.title3.bold())
                                .foregroundStyle(.blue)
                        )
                }
                VStack(alignment: .leading) {
                    Text(share.displayName).font(.headline)
                    Text("@\(share.handle)").font(.caption).foregroundStyle(.secondary)
                    Text(sharedSince).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
            .padding()
        }
    }
}
