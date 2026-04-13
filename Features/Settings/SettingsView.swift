// Features/Settings/SettingsView.swift
// Rosemount
//
// App settings sheet.  Accessible from the Profile tab toolbar.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// AuthManager      — Core/Auth/AuthManager.swift
// LicensesView     — Features/Settings/LicensesView.swift
// URLHealthChecker — Core/Rosemount/URLHealthChecker.swift
// AvatarView       — Shared/Components/AvatarView.swift
// OnboardingView   — Features/Onboarding/OnboardingView.swift

struct SettingsView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingSignOutConfirm = false
    @State private var showingAddAccount = false
    @StateObject private var healthChecker = URLHealthChecker()

    var body: some View {
        NavigationStack {
            List {

                // MARK: Accounts

                Section(String(localized: "settings.account.section")) {
                    ForEach(authManager.accounts) { account in
                        AccountRow(account: account, isActive: account.id == authManager.activeAccount?.id) {
                            authManager.switchAccount(to: account)
                        } onRemove: {
                            authManager.removeAccount(account)
                        }
                    }
                    Button {
                        showingAddAccount = true
                    } label: {
                        Label(String(localized: "settings.add_account"), systemImage: "plus.circle")
                    }
                }

                // MARK: Notifications

                Section(String(localized: "tab.notifications")) {
                    Button(String(localized: "settings.notifications")) {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                // MARK: About

                Section(String(localized: "settings.about.section")) {
                    LabeledContent(String(localized: "settings.version")) {
                        Text("\(AppStoreConfig.currentVersion) (\(AppStoreConfig.buildNumber))")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink(String(localized: "settings.licenses")) {
                        LicensesView()
                    }

                    NavigationLink(String(localized: "settings.accessibility")) {
                        AccessibilityAuditView()
                    }

                    if let privacyURL = URL(string: AppStoreConfig.privacyPolicyURL) {
                        Link(String(localized: "settings.privacy_policy"), destination: privacyURL)
                    }
                    if let termsURL = URL(string: AppStoreConfig.marketingURL + "/terms") {
                        Link(String(localized: "settings.terms"), destination: termsURL)
                    }
                    if let supportURL = URL(string: AppStoreConfig.supportURL) {
                        Link(String(localized: "settings.support"), destination: supportURL)
                    }
                }

                // MARK: Deployment Health (DEBUG builds only)

                #if DEBUG
                Section {
                    ForEach(healthChecker.results) { result in
                        HStack {
                            Image(systemName: result.status.isHealthy ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.status.isHealthy ? .green : .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.label).font(.subheadline)
                                Text(result.status.displayString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button(healthChecker.isChecking ? "Checking…" : "Run Health Checks") {
                        Task { await healthChecker.checkAll() }
                    }
                    .disabled(healthChecker.isChecking)
                } header: {
                    Text("Deployment Health")
                } footer: {
                    Text(healthChecker.summary)
                }
                #endif

                // MARK: Danger zone

                Section {
                    Button(String(localized: "settings.sign_out"), role: .destructive) {
                        showingSignOutConfirm = true
                    }
                }
            }
            .navigationTitle(String(localized: "settings.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "action.done")) { dismiss() }
                }
            }
            .confirmationDialog(
                String(localized: "settings.sign_out.confirm"),
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button(String(localized: "settings.sign_out"), role: .destructive) {
                    authManager.signOut()
                    dismiss()
                }
                Button(String(localized: "compose.cancel"), role: .cancel) {}
            } message: {
                Text(String(localized: "settings.sign_out.message"))
            }
            .sheet(isPresented: $showingAddAccount) {
                OnboardingView()
                    .environment(authManager)
            }
        }
    }
}

// MARK: - AccountRow

private struct AccountRow: View {
    let account: AccountCredential
    let isActive: Bool
    let onSwitch: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(url: account.avatarURL, size: 36, shape: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? "@\(account.handle)")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text("@\(account.handle) · \(account.instanceURL.host ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.accentColor)
                    .accessibilityLabel("Active account")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { if !isActive { onSwitch() } }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if !isActive {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(AuthManager.shared)
}
#endif
