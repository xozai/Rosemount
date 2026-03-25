// Features/VoiceRooms/VoiceRoomViewModel.swift

import Foundation
import Observation

@Observable
@MainActor
final class VoiceRoomViewModel: WebRTCSignalingDelegate {
    var room: VoiceRoom
    var speakers: [VoiceRoomSpeaker] = []
    var listenerCount: Int = 0
    var isMuted: Bool = true
    var handRaised: Bool = false
    var isConnected: Bool = false
    var isConnecting: Bool = false
    var error: Error?
    var isSpeaker: Bool = false
    var signalingUnavailable: Bool = false

    let audioEngine = VoiceAudioEngine()
    private var signalingClient: WebRTCSignalingClient?
    private var apiClient: VoiceRoomAPIClient?
    private var credential: AccountCredential?
    private var pollTask: Task<Void, Never>?

    init(room: VoiceRoom) {
        self.room = room
        self.speakers = room.speakers
        self.listenerCount = room.listenerCount
    }

    func setup(with credential: AccountCredential) {
        self.credential = credential
        apiClient = VoiceRoomAPIClient(instanceURL: credential.instanceURL, accessToken: credential.accessToken)
    }

    /// Attempts a WebSocket handshake to verify signaling server reachability.
    /// Returns `true` when the server is reachable within 5 seconds.
    func checkSignalingConnectivity() async -> Bool {
        guard let apiClient else { return false }
        let sigURL = await apiClient.signalingURL(roomId: room.id)
        return await withCheckedContinuation { continuation in
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: sigURL)
            var finished = false
            let lock = NSLock()
            task.resume()
            task.receive { result in
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                task.cancel(with: .normalClosure, reason: nil)
                continuation.resume(returning: true)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                task.cancel(with: .goingAway, reason: nil)
                continuation.resume(returning: false)
            }
        }
    }

    func join() async {
        guard let apiClient, let credential else { return }
        let reachable = await checkSignalingConnectivity()
        guard reachable else {
            signalingUnavailable = true
            return
        }
        isConnecting = true
        do {
            let joined = try await apiClient.joinRoom(id: room.id)
            room = joined
            speakers = joined.speakers
            listenerCount = joined.listenerCount
            isSpeaker = joined.speakers.contains { $0.account.id == credential.id.uuidString }

            // Start signaling
            let client = WebRTCSignalingClient(roomId: room.id, senderId: credential.id.uuidString)
            client.delegate = self
            signalingClient = client
            let sigURL = await apiClient.signalingURL(roomId: room.id)
            client.connect(to: sigURL)

            // Start audio if speaker
            if isSpeaker {
                try? audioEngine.start()
            }

            isConnected = true
            startPolling()
        } catch {
            self.error = error
        }
        isConnecting = false
    }

    func leave() async {
        guard let apiClient else { return }
        stopPolling()
        signalingClient?.disconnect()
        audioEngine.stop()
        isConnected = false
        try? await apiClient.leaveRoom(id: room.id)
    }

    func toggleMute() {
        isMuted.toggle()
        audioEngine.setMuted(isMuted)
        signalingClient?.sendMuteUpdate(isMuted: isMuted)
        // Update local speaker entry
        if let idx = speakers.firstIndex(where: { $0.account.id == credential?.id.uuidString }) {
            speakers[idx] = VoiceRoomSpeaker(
                id: speakers[idx].id,
                account: speakers[idx].account,
                isMuted: isMuted,
                isSpeaking: speakers[idx].isSpeaking,
                isModerator: speakers[idx].isModerator,
                handRaised: speakers[idx].handRaised
            )
        }
    }

    func toggleHandRaise() {
        handRaised.toggle()
        signalingClient?.sendHandRaise(handRaised)
    }

    func isHost() -> Bool {
        room.hostId == credential?.id.uuidString
    }

    // MARK: Polling

    private func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                await refreshRoom()
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func refreshRoom() async {
        guard let apiClient else { return }
        if let updated = try? await apiClient.room(id: room.id) {
            room = updated
            speakers = updated.speakers
            listenerCount = updated.listenerCount
        }
    }

    // MARK: WebRTCSignalingDelegate

    nonisolated func signalingDidConnect() {
        Task { @MainActor in self.isConnected = true }
    }

    nonisolated func signalingDidDisconnect() {
        Task { @MainActor in self.isConnected = false }
    }

    nonisolated func signalingDidReceiveMessage(_ message: SignalingMessage) {
        Task { @MainActor in self.handleSignalingMessage(message) }
    }

    nonisolated func signalingDidFail(with error: Error) {
        Task { @MainActor in self.error = error }
    }

    private func handleSignalingMessage(_ message: SignalingMessage) {
        switch message.type {
        case .mute:
            if let idx = speakers.firstIndex(where: { $0.account.id == message.senderId }) {
                speakers[idx] = VoiceRoomSpeaker(
                    id: speakers[idx].id, account: speakers[idx].account,
                    isMuted: true, isSpeaking: false,
                    isModerator: speakers[idx].isModerator, handRaised: speakers[idx].handRaised
                )
            }
        case .unmute:
            if let idx = speakers.firstIndex(where: { $0.account.id == message.senderId }) {
                speakers[idx] = VoiceRoomSpeaker(
                    id: speakers[idx].id, account: speakers[idx].account,
                    isMuted: false, isSpeaking: speakers[idx].isSpeaking,
                    isModerator: speakers[idx].isModerator, handRaised: speakers[idx].handRaised
                )
            }
        case .raiseHand:
            if let idx = speakers.firstIndex(where: { $0.account.id == message.senderId }) {
                speakers[idx] = VoiceRoomSpeaker(
                    id: speakers[idx].id, account: speakers[idx].account,
                    isMuted: speakers[idx].isMuted, isSpeaking: speakers[idx].isSpeaking,
                    isModerator: speakers[idx].isModerator, handRaised: true
                )
            }
        case .lowerHand:
            if let idx = speakers.firstIndex(where: { $0.account.id == message.senderId }) {
                speakers[idx] = VoiceRoomSpeaker(
                    id: speakers[idx].id, account: speakers[idx].account,
                    isMuted: speakers[idx].isMuted, isSpeaking: speakers[idx].isSpeaking,
                    isModerator: speakers[idx].isModerator, handRaised: false
                )
            }
        case .promote:
            // A listener was promoted to speaker — refresh room to get updated speaker list.
            Task { await refreshRoom() }
        case .kick:
            // Current user was removed from the room.
            if message.targetId == credential?.id.uuidString {
                isConnected = false
            } else {
                speakers.removeAll { $0.account.id == message.targetId }
            }
        default:
            Task { await refreshRoom() }
        }
    }
}
