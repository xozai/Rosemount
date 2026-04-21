// NetworkMonitor.swift
// Rosemount
//
// Observes network path changes via NWPathMonitor and publishes
// the current reachability status. Uses @Observable so it integrates
// naturally with SwiftUI's @Environment.
//
// Swift 5.10 | iOS 17.0+

import Foundation
import Network
import Observation

// MARK: - NetworkMonitor

@Observable
@MainActor
final class NetworkMonitor {

    // MARK: - Published State

    /// `true` when the device has a usable network path.
    private(set) var isConnected: Bool = true

    // MARK: - Private

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "social.rosemount.networkmonitor", qos: .utility)

    // MARK: - Init / Lifecycle

    nonisolated init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor [weak self] in self?.isConnected = connected }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
    }

    // MARK: - Shared Instance

    static let shared = NetworkMonitor()
}
