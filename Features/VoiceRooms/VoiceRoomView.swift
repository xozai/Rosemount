// Features/VoiceRooms/VoiceRoomView.swift
// Live voice room UI (Clubhouse-style)

import SwiftUI

struct VoiceRoomView: View {
    @State private var viewModel: VoiceRoomViewModel
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingLeaveConfirm = false

    init(room: VoiceRoom) {
        _viewModel = State(initialValue: VoiceRoomViewModel(room: room))
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    colors: [Color(.systemBackground), Color.blue.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    // Room header
                    VStack(spacing: 8) {
                        Text(viewModel.room.title)
                            .font(.title2.bold())
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)

                        // Tags
                        if !viewModel.room.topicTags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(viewModel.room.topicTags, id: \.self) { tag in
                                        Text("#\(tag)")
                                            .font(.caption)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(.blue.opacity(0.1), in: Capsule())
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: "person.2.fill")
                                .font(.caption)
                            Text("\(viewModel.listenerCount) listening")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .padding(.top)

                    Divider().padding(.vertical, 12)

                    // Speakers grid
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 4), spacing: 20) {
                            ForEach(viewModel.speakers) { speaker in
                                SpeakerAvatarView(speaker: speaker)
                            }
                        }
                        .padding()
                    }

                    Spacer()

                    // Control bar
                    if viewModel.isConnected {
                        controlBar
                            .padding(.bottom, 34)
                    } else if viewModel.isConnecting {
                        ProgressView("Joining room…")
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingLeaveConfirm = true } label: {
                        Text("Leave").foregroundStyle(.red)
                    }
                }
            }
            .confirmationDialog(
                viewModel.isHost() ? "End Room?" : "Leave Room?",
                isPresented: $showingLeaveConfirm,
                titleVisibility: .visible
            ) {
                Button(viewModel.isHost() ? "End Room for Everyone" : "Leave Quietly", role: .destructive) {
                    Task { await viewModel.leave(); dismiss() }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: .constant(viewModel.error != nil), presenting: viewModel.error) { _ in
                Button("OK") { viewModel.error = nil }
            } message: { err in
                Text(err.localizedDescription)
            }
            .alert(
                "Voice Rooms Unavailable",
                isPresented: $viewModel.signalingUnavailable
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Voice Rooms are not available right now. Please try again later.")
            }
        }
        .task {
            if let account = authManager.activeAccount {
                viewModel.setup(with: account)
                await viewModel.join()
            }
        }
    }

    private var controlBar: some View {
        HStack(spacing: 40) {
            // Mute / unmute (only for speakers)
            if viewModel.isSpeaker {
                Button {
                    viewModel.toggleMute()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(viewModel.isMuted ? Color.red.opacity(0.15) : Color.green.opacity(0.15))
                                .frame(width: 60, height: 60)
                            Image(systemName: viewModel.isMuted ? "mic.slash.fill" : "mic.fill")
                                .font(.title2)
                                .foregroundStyle(viewModel.isMuted ? .red : .green)
                        }
                        Text(viewModel.isMuted ? "Unmute" : "Mute")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            } else {
                // Raise hand (for listeners)
                Button { viewModel.toggleHandRaise() } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(viewModel.handRaised ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.1))
                                .frame(width: 60, height: 60)
                            Image(systemName: "hand.raised.fill")
                                .font(.title2)
                                .foregroundStyle(viewModel.handRaised ? .orange : .secondary)
                        }
                        Text(viewModel.handRaised ? "Lower Hand" : "Raise Hand")
                            .font(.caption)
                            .foregroundStyle(.primary)
                    }
                }
                .buttonStyle(.plain)
            }

            // Audio level indicator (only when unmuted + speaker)
            if viewModel.isSpeaker && !viewModel.isMuted {
                AudioLevelIndicator(level: viewModel.audioEngine.inputLevel)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal)
    }
}

// MARK: - Speaker Avatar

struct SpeakerAvatarView: View {
    let speaker: VoiceRoomSpeaker
    @State private var speakingScale: Double = 1.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if speaker.isSpeaking && !speaker.isMuted {
                    Circle()
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 64, height: 64)
                        .scaleEffect(speakingScale)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: speakingScale)
                        .onAppear { speakingScale = 1.12 }
                }

                AsyncImage(url: URL(string: speaker.account.avatar)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(.gray.opacity(0.3))
                        .overlay(
                            Text(String(speaker.account.displayName.prefix(1)))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        )
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())

                // Badges
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        ZStack {
                            if speaker.isModerator {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                    .padding(3)
                                    .background(.white, in: Circle())
                            } else if speaker.isMuted {
                                Image(systemName: "mic.slash.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                                    .padding(3)
                                    .background(.white, in: Circle())
                            } else if speaker.handRaised {
                                Text("✋")
                                    .font(.caption2)
                                    .padding(2)
                                    .background(.white, in: Circle())
                            }
                        }
                    }
                }
                .frame(width: 56, height: 56)
            }
            .frame(width: 64, height: 64)

            Text(speaker.account.displayName)
                .font(.caption2)
                .lineLimit(1)
                .frame(width: 64)
        }
    }
}

// MARK: - Audio Level Indicator

struct AudioLevelIndicator: View {
    let level: Float
    private let barCount = 5

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                let threshold = Float(i + 1) / Float(barCount)
                RoundedRectangle(cornerRadius: 2)
                    .fill(level > threshold ? Color.green : Color.green.opacity(0.2))
                    .frame(width: 4, height: 6 + CGFloat(i) * 4)
            }
        }
        .animation(.easeOut(duration: 0.1), value: level)
    }
}

// MARK: - Voice Rooms List

struct VoiceRoomsListView: View {
    let communitySlug: String?

    var body: some View {
        // Voice Rooms are in active development — show a Coming Soon placeholder
        // until the WebRTC peer-connection layer is complete.
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "waveform.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Voice Rooms")
                .font(.title2.bold())
            Text("Live audio rooms are coming soon.\nJoin your community and talk in real time.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Voice Rooms")
    }
}
