// Core/VoiceRooms/VoiceAudioEngine.swift
// AVAudioEngine-based capture and playback engine for Voice Rooms.
//
// Responsibilities:
//   - Captures microphone input and measures real-time input level (VU meter).
//   - Applies mute state by zeroing the tap buffer before it reaches the mixer.
//   - Exposes `inputLevel: Float` for the audio-level indicator in VoiceRoomView.
//
// Swift 5.10 | iOS 17.0+

import AVFoundation
import OSLog

private let logger = Logger(subsystem: "social.rosemount", category: "VoiceAudioEngine")

// MARK: - VoiceAudioEngine

/// Lightweight wrapper around `AVAudioEngine` that handles microphone capture,
/// real-time level metering, and mute toggling for Voice Rooms.
@Observable
final class VoiceAudioEngine {

    // MARK: - Observable State

    /// Normalised input level in the range `[0, 1]`, updated ~10× per second.
    /// Drives the `AudioLevelIndicator` in `VoiceRoomView`.
    private(set) var inputLevel: Float = 0

    // MARK: - Private State

    private let engine = AVAudioEngine()
    private var isMuted: Bool = true
    private var isRunning: Bool = false

    // Level metering is derived by calculating RMS over the tap buffer.
    private let levelSmoothingFactor: Float = 0.3

    // MARK: - Lifecycle

    /// Starts the audio engine and installs the input tap.
    ///
    /// Call `WebRTCAudioSession.shared.activate()` before this method.
    func start() throws {
        guard !isRunning else { return }

        let inputNode   = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        try engine.start()
        isRunning = true
        logger.info("VoiceAudioEngine started.")
    }

    /// Stops the audio engine and removes the tap.
    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        inputLevel = 0
        logger.info("VoiceAudioEngine stopped.")
    }

    /// Sets the mute state. When muted, the input level reads `0` and audio
    /// data is not forwarded to the mixer (microphone remains captured but silenced).
    func setMuted(_ muted: Bool) {
        isMuted = muted
        if muted { inputLevel = 0 }
    }

    // MARK: - Buffer Processing

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted,
              let channelData = buffer.floatChannelData
        else {
            DispatchQueue.main.async { [weak self] in self?.inputLevel = 0 }
            return
        }

        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Compute RMS over the first channel.
        let channelPtr = channelData[0]
        var rms: Float = 0
        for i in 0..<frameLength {
            rms += channelPtr[i] * channelPtr[i]
        }
        rms = sqrt(rms / Float(frameLength))

        // Convert to dB, normalise to [0, 1] from [-60 dB, 0 dB].
        let dB = 20 * log10(max(rms, 1e-7))
        let normalised = max(0, min(1, (dB + 60) / 60))

        // Smooth the level to avoid jitter.
        let smoothed = levelSmoothingFactor * normalised + (1 - levelSmoothingFactor) * inputLevel

        DispatchQueue.main.async { [weak self] in
            self?.inputLevel = smoothed
        }
    }
}
