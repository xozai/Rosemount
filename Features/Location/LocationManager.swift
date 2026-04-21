// Features/Location/LocationManager.swift
// CoreLocation wrapper with live-sharing controls

import CoreLocation
import Foundation
import Observation

extension CLAuthorizationStatus {
    var isAuthorized: Bool {
        self == .authorizedWhenInUse || self == .authorizedAlways
    }
}

@Observable
@MainActor
final class LocationManager: NSObject {
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?
    var isSharing: Bool = false
    var sharingDuration: SharingDuration = .oneHour
    var sharingExpiry: Date?
    var error: Error?

    private let manager = CLLocationManager()
    private var sharingTask: Task<Void, Never>?
    private var apiClient: LocationSharingAPIClient?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorizationStatus = manager.authorizationStatus
    }

    func setup(with credential: AccountCredential) {
        apiClient = LocationSharingAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startLiveSharing(duration: SharingDuration, communityId: String?) async {
        guard let client = apiClient else { return }
        guard authorizationStatus.isAuthorized else {
            requestPermission()
            return
        }
        manager.startUpdatingLocation()
        // Wait briefly for first location
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard let loc = currentLocation else { return }

        do {
            _ = try await client.startSharing(location: loc, duration: duration, communityId: communityId)
            isSharing = true
            sharingDuration = duration
            if let secs = duration.actualDuration {
                sharingExpiry = Date().addingTimeInterval(secs)
            }

            sharingTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 30_000_000_000) // 30s
                    if Task.isCancelled { break }
                    if let expiry = sharingExpiry, Date() >= expiry {
                        await stopSharing()
                        break
                    }
                    if let loc = currentLocation {
                        do {
                            try await client.updateLocation(loc)
                        } catch {
                            self.error = error
                        }
                    }
                }
            }
        } catch {
            self.error = error
        }
    }

    func stopSharing() async {
        sharingTask?.cancel()
        sharingTask = nil
        isSharing = false
        sharingExpiry = nil
        manager.stopUpdatingLocation()
        do {
            try await apiClient?.stopSharing()
        } catch {
            self.error = error
        }
    }

    var timeUntilExpiry: String? {
        guard isSharing else { return nil }
        guard let expiry = sharingExpiry else { return "Sharing until turned off" }
        let remaining = expiry.timeIntervalSinceNow
        if remaining <= 0 { return nil }
        let mins = Int(remaining / 60)
        let hours = mins / 60
        if hours > 0 { return "Sharing for \(hours)h \(mins % 60)m more" }
        return "Sharing for \(mins) more minutes"
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in self.currentLocation = loc }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.authorizationStatus = manager.authorizationStatus }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.error = error }
    }
}
