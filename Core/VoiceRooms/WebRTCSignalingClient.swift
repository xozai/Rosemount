// Core/VoiceRooms/WebRTCSignalingClient.swift
// WebSocket-based WebRTC signaling client

import AVFoundation
import Foundation
import Observation

// MARK: - Signaling State

enum SignalingState {
    case disconnected, connecting, connected, error(Error)
}

// MARK: - Signaling Client Delegate

protocol WebRTCSignalingDelegate: AnyObject {
    func signalingDidConnect()
    func signalingDidDisconnect()
    func signalingDidReceiveMessage(_ message: SignalingMessage)
    func signalingDidFail(with error: Error)
}

// MARK: - WebRTC Signaling Client

final class WebRTCSignalingClient: NSObject {
    private var webSocketTask: URLSessionWebSocketTask?
    private let session: URLSession
    weak var delegate: WebRTCSignalingDelegate?
    private(set) var state: SignalingState = .disconnected
    private let roomId: String
    private let senderId: String

    init(roomId: String, senderId: String) {
        self.roomId = roomId
        self.senderId = senderId
        self.session = URLSession(configuration: .default)
        super.init()
    }

    func connect(to url: URL) {
        state = .connecting
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessages()
        sendJoin()
    }

    func disconnect() {
        sendLeave()
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        state = .disconnected
        delegate?.signalingDidDisconnect()
    }

    func send(_ message: SignalingMessage) {
        guard let data = try? JSONEncoder().encode(message),
              let string = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(string)) { _ in }
    }

    func sendMuteUpdate(isMuted: Bool) {
        let msg = SignalingMessage(
            type: isMuted ? .mute : .unmute,
            roomId: roomId,
            senderId: senderId,
            targetId: nil,
            payload: nil
        )
        send(msg)
    }

    func sendHandRaise(_ raised: Bool) {
        let msg = SignalingMessage(
            type: raised ? .raiseHand : .lowerHand,
            roomId: roomId,
            senderId: senderId,
            targetId: nil,
            payload: nil
        )
        send(msg)
    }

    // MARK: Private

    private func sendJoin() {
        let msg = SignalingMessage(type: .join, roomId: roomId, senderId: senderId, targetId: nil, payload: nil)
        send(msg)
    }

    private func sendLeave() {
        let msg = SignalingMessage(type: .leave, roomId: roomId, senderId: senderId, targetId: nil, payload: nil)
        send(msg)
    }

    private func receiveMessages() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                self.state = .connected
                switch message {
                case .string(let text):
                    if let data = text.data(using: .utf8),
                       let msg = try? JSONDecoder().decode(SignalingMessage.self, from: data) {
                        DispatchQueue.main.async { self.delegate?.signalingDidReceiveMessage(msg) }
                    }
                case .data(let data):
                    if let msg = try? JSONDecoder().decode(SignalingMessage.self, from: data) {
                        DispatchQueue.main.async { self.delegate?.signalingDidReceiveMessage(msg) }
                    }
                @unknown default: break
                }
                self.receiveMessages()
            case .failure(let error):
                self.state = .error(error)
                DispatchQueue.main.async { self.delegate?.signalingDidFail(with: error) }
            }
        }
    }
}

// MARK: - Audio Engine

@Observable
@MainActor
final class VoiceAudioEngine {
    var isMuted: Bool = false
    var isActive: Bool = false
    var inputLevel: Float = 0.0
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var levelTimer: Timer?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self, !self.isMuted else { return }
            // In a full WebRTC implementation, this audio data would be encoded
            // and sent via the peer connection's audio track. Here we measure level.
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            guard let data = channelData else { return }
            let sum = (0..<frameLength).reduce(0.0) { $0 + abs(data[$1]) }
            let avg = frameLength > 0 ? sum / Float(frameLength) : 0
            Task { @MainActor in self.inputLevel = avg }
        }

        try engine.start()
        audioEngine = engine
        inputNode = input
        isActive = true
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        isActive = false
        inputLevel = 0
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func setMuted(_ muted: Bool) {
        isMuted = muted
    }
}
