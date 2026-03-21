// AppStore/AppStoreSubmissionGuide.swift
// App Store submission checklist and configuration constants

import Foundation

// MARK: - App Store Metadata

enum AppStoreConfig {
    static let appName = "Rosemount"
    static let bundleId = "com.rosemount.ios"
    static let appStoreCategory = "Social Networking"
    static let minimumOSVersion = "17.0"
    static let currentVersion = "1.0.0"
    static let buildNumber = "1"

    static let shortDescription = "Community-first social networking on the open web"

    static let fullDescription = """
    Rosemount is a community-first social network built on the open ActivityPub protocol. \
    Connect with communities that matter to you, share with your neighbors, and own your digital \
    presence — without algorithmic manipulation or ads.

    **Features:**
    • Communities — Organize around shared interests with their own feeds, events, and spaces
    • ActivityPub Federation — Follow people on Mastodon, Pixelfed, and other fediverse platforms
    • End-to-End Encrypted DMs — Private messages protected by the Signal Protocol
    • Voice Rooms — Drop into live audio rooms with your community
    • Stories — 24-hour ephemeral moments
    • Events — Organize meetups with RSVP, maps, and attendee lists
    • Photos — A beautiful photo timeline powered by Pixelfed
    • Polls — Get community input with expiring polls
    • Emoji Reactions — React beyond the Like button
    • Offline Mode — Read your feed without a connection

    Rosemount is open source. Your data stays on servers you choose.
    """

    static let keywords = [
        "social", "network", "community", "fediverse", "activitypub",
        "mastodon", "decentralized", "local", "open", "privacy"
    ].joined(separator: ", ")

    static let supportURL = "https://rosemount.social/support"
    static let marketingURL = "https://rosemount.social"
    static let privacyPolicyURL = "https://rosemount.social/privacy"

    // Age rating — 12+ (infrequent/mild suggestive themes from user content)
    static let ageRating = "12+"

    // Required device capabilities
    static let requiredDeviceCapabilities = [
        "arm64",
        "microphone"   // for Voice Rooms
    ]
}

// MARK: - Required Info.plist Keys

/*
 The following keys must be present in Info.plist before submission:

 NSCameraUsageDescription
   "Rosemount needs camera access to take photos for your stories and profile."

 NSPhotoLibraryUsageDescription
   "Rosemount needs photo library access to attach images to posts and stories."

 NSPhotoLibraryAddUsageDescription
   "Rosemount saves photos you download from the feed to your photo library."

 NSMicrophoneUsageDescription
   "Rosemount uses your microphone for Voice Rooms."

 NSLocationWhenInUseUsageDescription
   "Rosemount uses your approximate location to share it with your community when you choose to."

 NSFaceIDUsageDescription
   "Rosemount uses Face ID to securely unlock the app."

 NSUserNotificationsUsageDescription  (via UNUserNotificationCenter — no plist key needed)

 BGTaskSchedulerPermittedIdentifiers (array):
   com.rosemount.background.refresh
   com.rosemount.background.sync

 UIBackgroundModes (array):
   fetch
   processing
   audio               (for Voice Rooms background audio)
   remote-notification (for push)
*/

// MARK: - Pre-Submission Checklist

enum SubmissionChecklist {
    struct CheckItem {
        let category: String
        let item: String
        let notes: String
    }

    static let items: [CheckItem] = [
        // Technical
        CheckItem(category: "Technical", item: "All targets build without errors in Release mode", notes: "Product → Archive"),
        CheckItem(category: "Technical", item: "No use of private APIs or undocumented frameworks", notes: "Run `nm` to audit symbols if needed"),
        CheckItem(category: "Technical", item: "Privacy manifest (PrivacyManifest.xcprivacy) included in target", notes: "Required since Spring 2024"),
        CheckItem(category: "Technical", item: "All required Info.plist usage description strings present", notes: "See AppStoreConfig comment above"),
        CheckItem(category: "Technical", item: "BGTaskSchedulerPermittedIdentifiers set in Info.plist", notes: "Must match registered task IDs"),
        CheckItem(category: "Technical", item: "App does not crash on launch (cold + warm)", notes: "Test on oldest supported device (iPhone 12)"),
        CheckItem(category: "Technical", item: "App handles network unavailability gracefully", notes: "Enable offline mode on airplane mode"),
        CheckItem(category: "Technical", item: "All deep links and Universal Links functional", notes: "Test with `xcrun simctl openurl`"),

        // Design
        CheckItem(category: "Design", item: "App icon present in all required sizes (1024×1024 source)", notes: "No alpha channel on App Store icon"),
        CheckItem(category: "Design", item: "Launch screen configured (no placeholder)", notes: "LaunchScreen.storyboard or Info.plist key"),
        CheckItem(category: "Design", item: "Screenshots prepared for all required device sizes", notes: "6.7\", 6.5\", 5.5\", iPad Pro 12.9\""),
        CheckItem(category: "Design", item: "App preview video (optional but recommended)", notes: "Up to 30 seconds, .mov format"),
        CheckItem(category: "Design", item: "Dark mode and light mode both look correct", notes: "Test both in Simulator"),

        // Accessibility
        CheckItem(category: "Accessibility", item: "VoiceOver works on all primary flows", notes: "Test login → post → community flows"),
        CheckItem(category: "Accessibility", item: "Larger Text accessibility sizes don't break layout", notes: "Test at accessibility-xxLarge"),
        CheckItem(category: "Accessibility", item: "Reduce Motion respected throughout", notes: "Enable in Settings → Accessibility"),

        // Legal
        CheckItem(category: "Legal", item: "Privacy Policy URL is live and accurate", notes: AppStoreConfig.privacyPolicyURL),
        CheckItem(category: "Legal", item: "Terms of Service URL is live", notes: AppStoreConfig.marketingURL + "/terms"),
        CheckItem(category: "Legal", item: "Third-party license attributions included in Settings", notes: "Settings → About → Licenses"),
        CheckItem(category: "Legal", item: "Export compliance: no encryption beyond standard HTTPS", notes: "E2E encryption: select 'Yes' on export compliance, exemption applies"),

        // App Review
        CheckItem(category: "App Review", item: "Demo account credentials included in App Review notes", notes: "review@rosemount.social / ReviewPass2024!"),
        CheckItem(category: "App Review", item: "Backend demo server accessible from App Store review servers", notes: "Whitelist 17.0.0.0/8 if IP-restricted"),
        CheckItem(category: "App Review", item: "Review notes explain federated nature of the app", notes: "Reviewers may be confused by ActivityPub"),
        CheckItem(category: "App Review", item: "Content moderation and reporting flows functional", notes: "Reviewers will test reporting"),

        // Analytics
        CheckItem(category: "Analytics", item: "Crash reporting configured (e.g. MetricKit)", notes: "No third-party SDK required — MetricKit is built-in"),
        CheckItem(category: "Analytics", item: "App Store Connect analytics baseline established", notes: "Monitor impressions, conversion, crashes"),
    ]
}
