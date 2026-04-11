// OnboardingView.swift
// Rosemount
//
// The onboarding flow entry point. Shows the welcome screen, routes to
// instance entry, and displays a sign-in progress indicator.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// OnboardingViewModel         — Features/Onboarding/OnboardingViewModel.swift
// OnboardingStep              — Features/Onboarding/OnboardingViewModel.swift
// FederationPlatform          — Core/Auth/AuthManager.swift
// InstancePickerView          — Features/Onboarding/InstancePickerView.swift
// RosemountRegistrationView   — Features/Onboarding/RosemountRegistrationView.swift

// MARK: - OnboardingView

/// Root container for the onboarding / sign-in flow.
struct OnboardingView: View {

    @State private var viewModel = OnboardingViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .welcome:
                    OnboardingWelcomeView(viewModel: viewModel)

                case .instanceEntry:
                    InstancePickerView(viewModel: viewModel)

                case .registration:
                    RosemountRegistrationView(viewModel: viewModel)

                case .authenticating:
                    authenticatingView

                case .profileSetup:
                    // AuthManager.isAuthenticated flips to true and RootView switches to ContentView.
                    authenticatingView
                }
            }
            .animation(.easeInOut(duration: 0.3), value: viewModel.step)
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
    }

    // MARK: - Authenticating View

    private var authenticatingView: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.6)

            Text(String(localized: "onboarding.signing_in"))
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - OnboardingWelcomeView

/// Welcome screen shown on first launch.
struct OnboardingWelcomeView: View {

    @Bindable var viewModel: OnboardingViewModel
    @Environment(\.openURL) private var openURL

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Logo / Icon
            logoView
                .padding(.bottom, 32)

            // Title & Subtitle
            VStack(spacing: 8) {
                Text(String(localized: "onboarding.welcome.title"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)

                Text(String(localized: "onboarding.welcome.subtitle"))
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 48)

            // Sign-in buttons
            VStack(spacing: 14) {
                mastodonButton
                pixelfedButton
                rosemountButton
            }
            .padding(.horizontal, 32)

            Spacer()

            // Fediverse info link
            fediverseLink
                .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Subviews

    private var logoView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.8), Color.indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 100, height: 100)

            Text("R")
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }

    private var mastodonButton: some View {
        Button {
            viewModel.selectedPlatform = .mastodon
            viewModel.step = .instanceEntry
        } label: {
            Label("Sign in with Mastodon", systemImage: "person.badge.shield.checkmark")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlatformButtonStyle(color: Color(red: 0.38, green: 0.25, blue: 0.78))) // Mastodon purple
    }

    private var pixelfedButton: some View {
        Button {
            viewModel.selectedPlatform = .pixelfed
            viewModel.step = .instanceEntry
        } label: {
            Label("Sign in with Pixelfed", systemImage: "photo.stack")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlatformButtonStyle(color: Color(red: 0.00, green: 0.48, blue: 0.87))) // Pixelfed blue
    }

    private var rosemountButton: some View {
        Button {
            Task { await viewModel.signInWithRosemount() }
        } label: {
            Label("Create Rosemount Account", systemImage: "rosette")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(PlatformButtonStyle(
            color: Color(red: 0.80, green: 0.31, blue: 0.36),   // Rosemount rose
            style: .primary
        ))
    }

    private var fediverseLink: some View {
        Button {
            if let url = URL(string: "https://fediverse.info") {
                openURL(url)
            }
        } label: {
            HStack(spacing: 4) {
                Text("What is the Fediverse?")
                    .font(.subheadline)
                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - PlatformButtonStyle

/// A full-width rounded button style used for the sign-in options.
private struct PlatformButtonStyle: ButtonStyle {

    enum Style { case primary, secondary }

    let color: Color
    var style: Style = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .padding(.vertical, 14)
            .padding(.horizontal, 20)
            .background(backgroundView(pressed: configuration.isPressed))
            .foregroundStyle(style == .primary ? .white : color)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }

    @ViewBuilder
    private func backgroundView(pressed: Bool) -> some View {
        switch style {
        case .primary:
            color.opacity(pressed ? 0.8 : 1.0)
        case .secondary:
            Color(.secondarySystemBackground)
                .opacity(pressed ? 0.7 : 1.0)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Welcome") {
    OnboardingView()
}
#endif
