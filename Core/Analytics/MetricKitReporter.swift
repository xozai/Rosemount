// Core/Analytics/MetricKitReporter.swift
// Rosemount
//
// Subscribes to MetricKit payloads and forwards crash diagnostics + performance
// metrics to the app's backend for App Store Connect / Instruments analysis.
//
// Attach by calling `MetricKitReporter.shared.start()` from AppDelegate
// `application(_:didFinishLaunchingWithOptions:)`.
//
// Swift 5.10 | iOS 17.0+

import MetricKit
import OSLog

private let logger = Logger(subsystem: "social.rosemount", category: "MetricKit")

// MARK: - MetricKitReporter

final class MetricKitReporter: NSObject {

    // MARK: Singleton

    static let shared = MetricKitReporter()
    private override init() {}

    // MARK: Lifecycle

    /// Registers the reporter as a MetricKit subscriber.
    /// Call once from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    func start() {
        MXMetricManager.shared.add(self)
        logger.info("MetricKitReporter started — subscribed to MXMetricManager")
    }

    /// Removes the MetricKit subscription. Call from your app teardown if needed.
    func stop() {
        MXMetricManager.shared.remove(self)
        logger.info("MetricKitReporter stopped")
    }
}

// MARK: - MXMetricManagerSubscriber

extension MetricKitReporter: MXMetricManagerSubscriber {

    /// Receives daily metric payloads from the OS.
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            logger.info("Received MetricKit payload for \(payload.timeStampBegin) – \(payload.timeStampEnd)")
            processMetricPayload(payload)
        }
    }

    /// Receives on-device crash / hang / disk-write diagnostic payloads (iOS 14+).
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            logger.error("Received MetricKit diagnostic payload for \(payload.timeStampBegin) – \(payload.timeStampEnd)")
            processDiagnosticPayload(payload)
        }
    }
}

// MARK: - Payload Processing

private extension MetricKitReporter {

    func processMetricPayload(_ payload: MXMetricPayload) {
        // Log key performance metrics at debug level.
        if let launchMetrics = payload.applicationLaunchMetrics {
            let ttfr = launchMetrics.histogrammedTimeToFirstDraw
            logger.debug("Launch histogram: \(ttfr.bucketEnumerator.debugDescription)")
        }

        if let memoryMetrics = payload.memoryMetrics {
            logger.debug("Peak memory: \(memoryMetrics.peakMemoryUsage.value) \(memoryMetrics.peakMemoryUsage.unitDescription)")
        }

        if let diskMetrics = payload.diskIOMetrics {
            logger.debug("Disk writes: \(diskMetrics.cumulativeLogicalWrites.value) \(diskMetrics.cumulativeLogicalWrites.unitDescription)")
        }

        // Forward JSON payload to the telemetry endpoint (fire-and-forget).
        sendPayloadJSON(payload.jsonRepresentation(), type: "metrics")
    }

    func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        // Log crash call stacks for local diagnosis.
        if let crashDiagnostics = payload.crashDiagnostics {
            for crash in crashDiagnostics {
                logger.error("""
                    Crash diagnostic:
                      signal=\(crash.signal.debugDescription ?? "unknown")
                      terminationReason=\(crash.terminationReason ?? "none")
                    """)
            }
        }

        if let hangDiagnostics = payload.hangDiagnostics {
            for hang in hangDiagnostics {
                logger.error("Hang diagnostic: duration \(hang.hangDuration.value) \(hang.hangDuration.unitDescription)")
            }
        }

        // Forward to the telemetry endpoint.
        sendPayloadJSON(payload.jsonRepresentation(), type: "diagnostics")
    }

    /// Sends the MetricKit JSON payload to the Rosemount telemetry endpoint.
    /// Failures are logged but never surfaced to the user.
    func sendPayloadJSON(_ jsonData: Data, type payloadType: String) {
        // Replace with your real telemetry ingestion endpoint.
        guard let url = URL(string: "https://api.rosemount.social/api/v1/telemetry/metrickit") else {
            logger.error("Invalid MetricKit telemetry URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(payloadType, forHTTPHeaderField: "X-Payload-Type")
        request.httpBody = jsonData

        Task {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    logger.debug("MetricKit \(payloadType) payload uploaded successfully")
                } else {
                    logger.warning("MetricKit \(payloadType) upload returned non-200 response")
                }
            } catch {
                logger.error("MetricKit \(payloadType) upload failed: \(error.localizedDescription)")
            }
        }
    }
}
