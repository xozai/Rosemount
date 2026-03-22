// Features/Settings/SettingsView.swift
// Rosemount
//
// App settings sheet.  Accessible from the Profile tab toolbar.
//
// Swift 5.10 | iOS 17.0+

import SwiftUI

// AuthManager — Core/Auth/AuthManager.swift
// LicensesView — Features/Settings/LicensesView.swift

struct SettingsView: View {

    @Environment(AuthManager.self) private var authManager
    @Environment(\.dismiss) private var dismiss

    @State private var showingSignOutConfirm = false

    var body: some View {
        NavigationStack {
            List {

                // MARK: Account

                Section("Account") {
                    if let account = authManager.activeAccount {
                        LabeledContent("Handle", value: "@\(account.handle)")
                        LabeledContent("Server", value: account.instanceURL.host ?? "")
                    }
                }

                // MARK: Notifications

                Section("Notifications") {
                    Button("Open Notification Settings") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                }

                // MARK: About

                Section("About") {
                    LabeledContent("Version") {
                        Text("\(AppStoreConfig.currentVersion) (\(AppStoreConfig.buildNumber))")
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink("Open Source Licenses") {
                        LicensesView()
                    }

                    Link("Privacy Policy", destination: URL(string: AppStoreConfig.privacyPolicyURL)!)
                    Link("Terms of Service", destination: URL(string: AppStoreConfig.marketingURL + "/terms")!)
                    Link("Support", destination: URL(string: AppStoreConfig.supportURL)!)
                }

                // MARK: Danger zone

                Section {
                    Button("Sign Out", role: .destructive) {
                        showingSignOutConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Sign out of Rosemount?",
                isPresented: $showingSignOutConfirm,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) {
                    authManager.signOut()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can sign back in at any time.")
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
