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
    @State private var rooms: [VoiceRoom] = []
    @State private var isLoading = false
    @State private var selectedRoom: VoiceRoom? = nil
    @State private var showingCreate = false
    @Environment(AuthManager.self) private var authManager
    private var apiClient: VoiceRoomAPIClient? {
        guard let acct = authManager.activeAccount else { return nil }
        return VoiceRoomAPIClient(instanceURL: acct.instanceURL, accessToken: acct.accessToken)
    }

    var body: some View {
        Group {
            if isLoading && rooms.isEmpty {
                ProgressView()
            } else if rooms.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle")
                        .font(.system(size: 52))
                        .foregroundStyle(.secondary)
                    Text("No live rooms right now")
                        .foregroundStyle(.secondary)
                    Button("Start a Room") { showingCreate = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(rooms) { room in
                    VoiceRoomRowView(room: room)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRoom = room }
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                }
                .listStyle(.plain)
                .refreshable { await loadRooms() }
            }
        }
        .navigationTitle("Voice Rooms")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: {
                    Label("New Room", systemImage: "plus")
                }
            }
        }
        .fullScreenCover(item: $selectedRoom) { room in
            VoiceRoomView(room: room).environment(authManager)
        }
        .sheet(isPresented: $showingCreate) {
            CreateVoiceRoomView(communitySlug: communitySlug)
                .environment(authManager)
                .onDisappear { Task { await loadRooms() } }
        }
        .task { await loadRooms() }
    }

    private func loadRooms() async {
        guard let client = apiClient else { return }
        isLoading = true
        rooms = (try? await client.liveRooms(communitySlug: communitySlug)) ?? []
        isLoading = false
    }
}

struct VoiceRoomRowView: View {
    let room: VoiceRoom
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.purple.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "waveform").font(.title3).foregroundStyle(.purple)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("LIVE").font(.caption2.bold()).foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.red, in: Capsule())
                    Text(room.title).font(.body.bold()).lineLimit(1)
                }
                Text("\(room.speakerCount) speakers · \(room.listenerCount) listening")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary).font(.caption)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

struct CreateVoiceRoomView: View {
    let communitySlug: String?
    @State private var title = ""
    @State private var tags = ""
    @State private var isCreating = false
    @State private var createdRoom: VoiceRoom? = nil
    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Room Details") {
                    TextField("Room title", text: $title)
                    TextField("Topic tags (comma separated)", text: $tags)
                }
            }
            .navigationTitle("New Voice Room")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task {
                            guard let acct = authManager.activeAccount else { return }
                            isCreating = true
                            let client = VoiceRoomAPIClient(instanceURL: acct.instanceURL, accessToken: acct.accessToken)
                            let tagList = tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            if let room = try? await client.createRoom(title: title, communitySlug: communitySlug, topicTags: tagList) {
                                createdRoom = room
                                dismiss()
                            }
                            isCreating = false
                        }
                    }
                    .disabled(title.count < 3 || isCreating)
                }
            }
        }
    }
}
