// Core/VoiceRooms/WebRTCSignalingClient.swift
// WebSocket-based WebRTC signaling client

import Foundation

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

