// Features/Polls/PollVoteView.swift
// Display and vote on a poll embedded in a post

import Foundation
import SwiftUI

@Observable
@MainActor
final class PollVoteViewModel {
    var poll: MastodonPoll
    var selectedOptions: Set<Int> = []
    var isVoting: Bool = false
    var error: Error?

    init(poll: MastodonPoll) {
        self.poll = poll
    }

    var isExpired: Bool {
        guard let expiresAt = poll.expiresAt else { return false }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        let date = iso.date(from: expiresAt) ?? iso2.date(from: expiresAt)
        return (date ?? Date()) < Date()
    }

    var hasVoted: Bool { !(poll.ownVotes?.isEmpty ?? true) }
    var totalVotes: Int { poll.votesCount }

    func toggleOption(_ index: Int) {
        guard !hasVoted && !isExpired else { return }
        if poll.multiple {
            if selectedOptions.contains(index) { selectedOptions.remove(index) }
            else { selectedOptions.insert(index) }
        } else {
            selectedOptions = [index]
        }
    }

    func vote(with credential: AccountCredential) async {
        guard !selectedOptions.isEmpty else { return }
        isVoting = true
        do {
            var req = URLRequest(url: credential.instanceURL.appendingPathComponent("api/v1/polls/\(poll.id)/votes"))
            req.httpMethod = "POST"
            req.setValue("Bearer \(credential.accessToken)", forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: ["choices": Array(selectedOptions).sorted()])
            let (data, _) = try await URLSession.shared.data(for: req)
            poll = try JSONDecoder().decode(MastodonPoll.self, from: data)
        } catch {
            self.error = error
        }
        isVoting = false
    }
}

struct PollVoteView: View {
    @State private var viewModel: PollVoteViewModel
    let credential: AccountCredential?

    init(poll: MastodonPoll, credential: AccountCredential?) {
        _viewModel = State(initialValue: PollVoteViewModel(poll: poll))
        self.credential = credential
    }

    private var expiryText: String {
        guard let expiresAt = viewModel.poll.expiresAt else { return "No expiry" }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso2 = ISO8601DateFormatter()
        iso2.formatOptions = [.withInternetDateTime]
        guard let date = iso.date(from: expiresAt) ?? iso2.date(from: expiresAt) else { return "" }
        if viewModel.isExpired { return "Closed" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return "Closes " + f.localizedString(for: date, relativeTo: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(viewModel.poll.options.enumerated()), id: \.offset) { index, option in
                PollOptionRow(
                    title: option.title ?? "",
                    votes: option.votesCount,
                    totalVotes: viewModel.totalVotes,
                    isSelected: viewModel.selectedOptions.contains(index),
                    isMultiple: viewModel.poll.multiple,
                    showResult: viewModel.hasVoted || viewModel.isExpired,
                    isOwnVote: viewModel.poll.ownVotes?.contains(index) ?? false
                )
                .contentShape(Rectangle())
                .onTapGesture { viewModel.toggleOption(index) }
            }

            HStack(spacing: 8) {
                Text("\(viewModel.totalVotes) votes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(expiryText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if viewModel.poll.multiple {
                    Text("·")
                        .foregroundStyle(.secondary)
                    Text("Choose all that apply")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.hasVoted && !viewModel.isExpired, let cred = credential {
                Button {
                    Task { await viewModel.vote(with: cred) }
                } label: {
                    Text(viewModel.isVoting ? "Voting…" : "Vote")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.selectedOptions.isEmpty || viewModel.isVoting)
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct PollOptionRow: View {
    let title: String
    let votes: Int?
    let totalVotes: Int
    let isSelected: Bool
    let isMultiple: Bool
    let showResult: Bool
    let isOwnVote: Bool

    private var percentage: Double {
        guard let v = votes, totalVotes > 0 else { return 0 }
        return Double(v) / Double(totalVotes)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            // Background bar
            if showResult {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOwnVote ? Color.blue.opacity(0.2) : Color.secondary.opacity(0.1))
                        .frame(width: geo.size.width * percentage)
                }
                .animation(.easeOut(duration: 0.5), value: percentage)
            }

            HStack {
                // Radio / checkbox
                Image(systemName: isSelected
                    ? (isMultiple ? "checkmark.square.fill" : "largecircle.fill.circle")
                    : (isMultiple ? "square" : "circle"))
                .foregroundStyle(isSelected ? .blue : .secondary)
                .font(.body)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                if showResult {
                    Text("\(Int(percentage * 100))%")
                        .font(.caption.bold())
                        .foregroundStyle(isOwnVote ? .blue : .secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue : Color.secondary.opacity(0.2), lineWidth: 1.5)
        )
    }
}
