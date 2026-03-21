// InstancePickerView.swift
// Rosemount
//
// Instance URL entry for Mastodon / Pixelfed sign-in.
// Provides a text field for manual entry and a curated list of popular instances.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI
import AuthenticationServices

// OnboardingViewModel — defined in Features/Onboarding/OnboardingViewModel.swift
// FederationPlatform  — defined in Core/Auth/AuthManager.swift

// MARK: - InstancePickerView

struct InstancePickerView: View {

    // MARK: - Properties

    @Bindable var viewModel: OnboardingViewModel
    @FocusState private var isURLFieldFocused: Bool

    // MARK: - Popular Instances

    private static let mastodonInstances: [(host: String, description: String)] = [
        ("mastodon.social",    "The original flagship Mastodon server"),
        ("fosstodon.org",      "Open source & technology community"),
        ("hachyderm.io",       "Tech & professional community"),
        ("infosec.exchange",   "Information security professionals"),
    ]

    private static let pixelfedInstances: [(host: String, description: String)] = [
        ("pixelfed.social",    "The flagship Pixelfed instance"),
        ("pixelfed.de",        "German Pixelfed community"),
    ]

    private var popularInstances: [(host: String, description: String)] {
        viewModel.selectedPlatform == .mastodon
            ? Self.mastodonInstances
            : Self.pixelfedInstances
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Form {
                // Custom URL entry
                Section {
                    TextField(
                        "e.g. mastodon.social",
                        text: $viewModel.instanceURLString
                    )
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($isURLFieldFocused)
                    .submitLabel(.continue)
                    .onSubmit {
                        guard !viewModel.instanceURLString.isEmpty,
                              !viewModel.isLoading else { return }
                        attemptSignIn()
                    }
                } header: {
                    Text("Your Instance")
                } footer: {
                    Text(footerText)
                }

                // Popular instances
                Section("Popular Instances") {
                    ForEach(popularInstances, id: \.host) { instance in
                        Button {
                            viewModel.instanceURLString = instance.host
                            isURLFieldFocused = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(instance.host)
                                        .font(.body)
                                        .foregroundStyle(.primary)

                                    Text(instance.description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if viewModel.instanceURLString == instance.host {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accentColor)
                                        .font(.subheadline.weight(.semibold))
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Button("Continue") {
                            isURLFieldFocused = false
                            attemptSignIn()
                        }
                        .fontWeight(.semibold)
                        .disabled(viewModel.instanceURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
                    }
                }

                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") {
                        viewModel.step = .welcome
                        viewModel.instanceURLString = ""
                    }
                }
            }
            // Loading overlay
            if viewModel.isLoading {
                loadingOverlay
            }
        }
        .alert("Sign-In Failed", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.error = nil }
        } message: {
            if let message = viewModel.error {
                Text(message)
            }
        }
        .onAppear {
            isURLFieldFocused = true
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.4)
                Text("Connecting to \(viewModel.instanceURLString)…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 40)
        }
    }

    // MARK: - Helpers

    private var navigationTitle: String {
        viewModel.selectedPlatform == .mastodon ? "Mastodon Instance" : "Pixelfed Instance"
    }

    private var footerText: String {
        switch viewModel.selectedPlatform {
        case .mastodon:
            return "Enter your Mastodon server's address, e.g. "mastodon.social" or "your.instance.xyz"."
        case .pixelfed:
            return "Enter your Pixelfed server's address, e.g. "pixelfed.social"."
        case .rosemount:
            return "Enter your Rosemount server's address."
        }
    }

    /// Resolves the presentation anchor from the current key window and kicks off sign-in.
    private func attemptSignIn() {
        guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let anchor = windowScene.windows.first(where: { $0.isKeyWindow }) else {
            viewModel.error = "Unable to determine the current window for sign-in. Please try again."
            return
        }

        Task {
            switch viewModel.selectedPlatform {
            case .mastodon:
                await viewModel.signInWithMastodon(presentationAnchor: anchor)
            case .pixelfed:
                await viewModel.signInWithPixelfed(presentationAnchor: anchor)
            case .rosemount:
                await viewModel.signInWithRosemount()
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Mastodon Instance Picker") {
    NavigationStack {
        InstancePickerView(viewModel: {
            let vm = OnboardingViewModel()
            vm.selectedPlatform = .mastodon
            return vm
        }())
    }
}

#Preview("Pixelfed Instance Picker") {
    NavigationStack {
        InstancePickerView(viewModel: {
            let vm = OnboardingViewModel()
            vm.selectedPlatform = .pixelfed
            return vm
        }())
    }
}
#endif
