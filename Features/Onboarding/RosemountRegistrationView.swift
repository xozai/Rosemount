// RosemountRegistrationView.swift
// Rosemount
//
// Native Rosemount account registration form.
// Collects username, email, and password and submits them to the
// Rosemount back-end via OnboardingViewModel.submitRegistration().
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// OnboardingViewModel — Features/Onboarding/OnboardingViewModel.swift

// MARK: - RosemountRegistrationView

struct RosemountRegistrationView: View {

    // MARK: - State

    @Bindable var viewModel: OnboardingViewModel

    @State private var username: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var agreedToTerms: Bool = false
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case username, email, password, confirmPassword
    }

    // MARK: - Validation

    private var usernameError: String? {
        guard !username.isEmpty else { return nil }
        if username.count < 3 { return "At least 3 characters" }
        if username.count > 30 { return "30 characters maximum" }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        if username.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return "Letters, numbers and underscores only"
        }
        return nil
    }

    private var emailError: String? {
        guard !email.isEmpty else { return nil }
        return email.contains("@") && email.contains(".") ? nil : "Enter a valid email address"
    }

    private var passwordError: String? {
        guard !password.isEmpty else { return nil }
        return password.count >= 8 ? nil : "At least 8 characters"
    }

    private var confirmPasswordError: String? {
        guard !confirmPassword.isEmpty else { return nil }
        return confirmPassword == password ? nil : "Passwords do not match"
    }

    private var canSubmit: Bool {
        !username.isEmpty && !email.isEmpty && !password.isEmpty && !confirmPassword.isEmpty
            && usernameError == nil && emailError == nil
            && passwordError == nil && confirmPasswordError == nil
            && agreedToTerms
            && !viewModel.isLoading
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {

                // Header
                VStack(spacing: 8) {
                    Text("Create Account")
                        .font(.largeTitle.bold())
                    Text("Join rosemount.social or your own instance.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 32)

                // Form
                VStack(spacing: 16) {
                    formField(
                        title: "Username",
                        placeholder: "yourhandle",
                        text: $username,
                        field: .username,
                        error: usernameError,
                        keyboardType: .asciiCapable,
                        autocapitalization: .never,
                        prefix: "@"
                    )

                    formField(
                        title: "Email address",
                        placeholder: "you@example.com",
                        text: $email,
                        field: .email,
                        error: emailError,
                        keyboardType: .emailAddress,
                        autocapitalization: .never
                    )

                    secureFormField(
                        title: "Password",
                        placeholder: "8+ characters",
                        text: $password,
                        field: .password,
                        error: passwordError
                    )

                    secureFormField(
                        title: "Confirm password",
                        placeholder: "Repeat password",
                        text: $confirmPassword,
                        field: .confirmPassword,
                        error: confirmPasswordError
                    )
                }
                .padding(.horizontal, 24)

                // Terms toggle
                Toggle(isOn: $agreedToTerms) {
                    Text("I agree to the [Terms of Service](https://rosemount.social/terms) and [Privacy Policy](https://rosemount.social/privacy)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.checkmark)
                .padding(.horizontal, 24)

                // Submit button
                Button {
                    Task { await viewModel.submitRegistration(
                        username: username,
                        email: email,
                        password: password
                    )}
                } label: {
                    Group {
                        if viewModel.isLoading {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Create Account")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(canSubmit ? Color.accentColor : Color(.systemGray4))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canSubmit)
                .padding(.horizontal, 24)

                // Back to welcome
                Button {
                    viewModel.step = .welcome
                } label: {
                    Text("Sign in with existing account")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Register")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Subviews

    @ViewBuilder
    private func formField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        error: String?,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences,
        prefix: String? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            HStack(spacing: 4) {
                if let prefix {
                    Text(prefix)
                        .foregroundStyle(.secondary)
                        .font(.body)
                }
                TextField(placeholder, text: text)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                    .submitLabel(.next)
                    .onSubmit { advanceFocus(from: field) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(error != nil ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1)
            )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func secureFormField(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        error: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.medium))

            SecureField(placeholder, text: text)
                .focused($focusedField, equals: field)
                .submitLabel(field == .confirmPassword ? .done : .next)
                .onSubmit { advanceFocus(from: field) }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(error != nil ? Color.red.opacity(0.6) : Color.clear, lineWidth: 1)
                )

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: - Helpers

    private func advanceFocus(from field: Field) {
        switch field {
        case .username:        focusedField = .email
        case .email:           focusedField = .password
        case .password:        focusedField = .confirmPassword
        case .confirmPassword: focusedField = nil
        }
    }
}

// MARK: - Checkmark Toggle Style

private struct CheckmarkToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : Color(.systemGray3))
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

extension ToggleStyle where Self == CheckmarkToggleStyle {
    static var checkmark: CheckmarkToggleStyle { CheckmarkToggleStyle() }
}

// MARK: - Preview

#if DEBUG
#Preview("Registration") {
    NavigationStack {
        RosemountRegistrationView(viewModel: OnboardingViewModel())
    }
}
#endif
