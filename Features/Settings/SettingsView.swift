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

                Section(String(localized: "settings.account.section")) {
                    if let account = authManager.activeAccount {
                        LabeledContent(String(localized: "settings.account.handle"), value: "@\(account.handle)")
                        LabeledContent(String(localized: "settings.account.server"), value: account.instanceURL.host ?? "")
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

                    Link(String(localized: "settings.privacy_policy"), destination: URL(string: AppStoreConfig.privacyPolicyURL)!)
                    Link(String(localized: "settings.terms"), destination: URL(string: AppStoreConfig.marketingURL + "/terms")!)
                    Link(String(localized: "settings.support"), destination: URL(string: AppStoreConfig.supportURL)!)
                }

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
        }
    }
}

#if DEBUG
#Preview {
    SettingsView()
        .environment(AuthManager.shared)
}
#endif
