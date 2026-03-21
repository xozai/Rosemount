// Features/Location/LiveLocationView.swift
// Live location sharing controls sheet

import MapKit
import SwiftUI

struct LiveLocationView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var locationManager = LocationManager()
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDuration: SharingDuration = .oneHour
    @State private var selectedCommunity: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if !locationManager.authorizationStatus.isAuthorized {
                    permissionView
                } else if locationManager.isSharing {
                    sharingActiveView
                } else {
                    startSharingView
                }
            }
            .navigationTitle("Location Sharing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            if let account = authManager.activeAccount {
                locationManager.setup(with: account)
            }
        }
    }

    // MARK: - Permission View

    private var permissionView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "location.slash.fill")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            VStack(spacing: 8) {
                Text("Location Access Required")
                    .font(.title2.bold())
                Text("Allow Rosemount to access your location to share it with your community.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            Button("Allow Location") {
                locationManager.requestPermission()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .padding()
    }

    // MARK: - Start Sharing View

    private var startSharingView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Map thumbnail
                Map()
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .blur(radius: 4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.ultraThinMaterial)
                    )
                    .overlay(
                        VStack {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(.blue)
                            Text("Approximate location")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    )
                    .padding(.horizontal)

                VStack(spacing: 6) {
                    Text("Share your approximate location")
                        .font(.title3.bold())
                    Text("Your exact location is never stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Duration").font(.headline)
                    Picker("Duration", selection: $selectedDuration) {
                        ForEach(SharingDuration.allCases) { dur in
                            Text(dur.displayName).tag(dur)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal)

                Button {
                    Task { await locationManager.startLiveSharing(duration: selectedDuration, communityId: selectedCommunity) }
                } label: {
                    Label("Start Sharing", systemImage: "location.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal)

                if let error = locationManager.error {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Sharing Active View

    @State private var pulseAnimation = false

    private var sharingActiveView: some View {
        VStack(spacing: 32) {
            Spacer()
            ZStack {
                Circle()
                    .fill(.green.opacity(0.2))
                    .frame(width: 120, height: 120)
                    .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                    .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulseAnimation)
                Circle()
                    .fill(.green.opacity(0.4))
                    .frame(width: 90, height: 90)
                Image(systemName: "location.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.green)
            }
            .onAppear { pulseAnimation = true }

            VStack(spacing: 8) {
                Text("Sharing Location")
                    .font(.title2.bold())
                if let expiry = locationManager.timeUntilExpiry {
                    Text(expiry)
                        .foregroundStyle(.secondary)
                }
            }

            Button(role: .destructive) {
                Task { await locationManager.stopSharing() }
            } label: {
                Label("Stop Sharing", systemImage: "location.slash.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .padding(.horizontal)

            Spacer()
        }
    }
}
