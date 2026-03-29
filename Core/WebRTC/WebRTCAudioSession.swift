// Core/WebRTC/WebRTCAudioSession.swift
// AVAudioSession configuration for Voice Rooms (WebRTC / voice-chat use case).
//
// Handles:
//   - Activating the audio session with the correct category and mode.
//   - Responding to interruptions (phone calls, Siri, other apps).
//   - Deactivating cleanly when the room is left.
//
// Swift 5.10 | iOS 17.0+

import AVFoundation
import OSLog

private let logger = Logger(subsystem: "social.rosemount", category: "WebRTCAudioSession")

// MARK: - WebRTCAudioSession

/// Manages the shared `AVAudioSession` for Voice Room audio capture and playback.
///
/// Call `activate()` before starting audio capture, and `deactivate()` after stopping.
/// The session is configured for voice chat: `.playAndRecord` category with the
/// `.voiceChat` mode, which applies echo cancellation and noise suppression.
final class WebRTCAudioSession {

    // MARK: - Singleton

    static let shared = WebRTCAudioSession()

    // MARK: - State

    private(set) var isActive: Bool = false
    private var interruptionTask: Task<Void, Never>?

    // MARK: - Init

    private init() {
        observeInterruptions()
    }

    // MARK: - Lifecycle

    /// Configures and activates the `AVAudioSession` for voice chat.
    ///
    /// Must be called from any context before starting `AVAudioEngine` capture.
    func activate() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .voiceChat,
                                options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        isActive = true
        logger.info("AVAudioSession activated for voice chat.")
    }

    /// Deactivates the `AVAudioSession`, restoring any previously active session.
    func deactivate() {
        guard isActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isActive = false
            logger.info("AVAudioSession deactivated.")
        } catch {
            logger.error("Failed to deactivate audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Interruption Handling

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard
            let info = notification.userInfo,
            let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
            logger.info("Audio session interrupted.")
            isActive = false

        case .ended:
            let optionsValue = info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                logger.info("Audio session interruption ended — attempting to resume.")
                try? activate()
            }

        @unknown default:
            break
        }
    }
}
