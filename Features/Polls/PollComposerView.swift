// Features/Polls/PollComposerView.swift
// Add a poll to a post (embedded in ComposeView)

import Foundation
import SwiftUI

enum PollExpiry: Int, CaseIterable, Identifiable {
    case oneHour = 3600
    case sixHours = 21600
    case oneDay = 86400
    case threeDays = 259200
    case sevenDays = 604800

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .sixHours: return "6 Hours"
        case .oneDay: return "1 Day"
        case .threeDays: return "3 Days"
        case .sevenDays: return "7 Days"
        }
    }
}

struct PollOption: Identifiable {
    let id = UUID()
    var text: String
}

@Observable
final class PollComposerViewModel {
    var options: [PollOption] = [PollOption(text: ""), PollOption(text: "")]
    var isMultipleChoice: Bool = false
    var expiryDuration: PollExpiry = .oneDay

    var canAddOption: Bool { options.count < 4 }

    func addOption() {
        guard canAddOption else { return }
        options.append(PollOption(text: ""))
    }

    func removeOption(at index: Int) {
        guard options.count > 2 else { return }
        options.remove(at: index)
    }

    var isValid: Bool {
        options.count >= 2 && options.allSatisfy { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var apiPayload: [String: Any] {
        [
            "options": options.map { $0.text },
            "expires_in": expiryDuration.rawValue,
            "multiple": isMultipleChoice
        ]
    }
}

struct PollComposerView: View {
    @Binding var viewModel: PollComposerViewModel
    @Binding var isEnabled: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Add Poll", isOn: $isEnabled)
                .font(.subheadline.bold())

            if isEnabled {
                VStack(spacing: 8) {
                    ForEach(Array(viewModel.options.enumerated()), id: \.element.id) { index, option in
                        HStack {
                            TextField("Option \(index + 1)", text: Binding(
                                get: { viewModel.options[index].text },
                                set: { viewModel.options[index].text = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            if viewModel.options.count > 2 {
                                Button {
                                    withAnimation { viewModel.removeOption(at: index) }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if viewModel.canAddOption {
                        Button {
                            withAnimation { viewModel.addOption() }
                        } label: {
                            HStack {
                                Image(systemName: "plus")
                                Text("Add option")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [5]))
                                    .foregroundStyle(.blue.opacity(0.6))
                            )
                            .foregroundStyle(.blue)
                        }
                        .buttonStyle(.plain)
                    }

                    HStack {
                        Toggle("Multiple choice", isOn: $viewModel.isMultipleChoice)
                            .font(.subheadline)
                        Spacer()
                    }

                    HStack {
                        Text("Closes after")
                            .font(.subheadline)
                        Spacer()
                        Picker("Duration", selection: $viewModel.expiryDuration) {
                            ForEach(PollExpiry.allCases) { exp in
                                Text(exp.displayName).tag(exp)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}
