# Rosemount

> Community social on the open web

![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-See%20LICENSE-lightgrey)

A native iOS social networking app built on the ActivityPub protocol, with full interoperability with Mastodon and Pixelfed.

---

## What is Rosemount?

Rosemount is designed for tight-knit communities — high school reunion groups, youth sports leagues, neighborhood associations, and hobby clubs. It combines familiar social features with the openness of the federated web, letting users sign in with an existing Mastodon or Pixelfed account (or register natively) and interact across the entire ActivityPub network.

---

## Features

**Social**
- Communities — public and private groups, invite by handle / link / QR code
- Home, Local, and Federated timelines
- Stories — 24-hour ephemeral story viewer and composer
- Polls — expiring polls with live vote counts
- Events — RSVP, attendee lists, MapKit integration
- Location Sharing — privacy-first, grid-snapped, auto-expiring
- Scheduled Posts
- Offline Mode — cached feed, draft posts, background sync

**Messaging**
- Direct Messages — end-to-end encrypted 1-on-1 and group chats (Double Ratchet / Signal Protocol)
- Voice Rooms — live audio rooms with hand-raise and WebRTC signaling
- Push Notifications — APNs + Mastodon Web Push (`POST /api/v1/push/subscription`)

**Discovery & Media**
- Photo Feed — 3-column Pixelfed-style grid with Home and Discover tabs, multi-photo posts with editing
- Explore — search, trending hashtags, people and community directory

**Platform**
- ActivityPub Federation — follows, boosts, emoji reactions, WebFinger discovery
- Sign in with Mastodon / Sign in with Pixelfed — OAuth 2.0 via `ASWebAuthenticationSession`
- Native Rosemount registration with self-hosted instance support
- Face ID / Touch ID biometric unlock
- Deep linking via `rosemount://` URL scheme and Universal Links

---

## Architecture

The app follows MVVM with the Swift Observation framework (`@Observable`) and strict actor isolation (`@MainActor` throughout). There are no third-party package dependencies — everything is built on Apple frameworks and the Swift standard library.

- **Navigation** — `AppCoordinator` (`ContentView`) manages a 7-tab `TabView`: Home, Communities, Events, Photos, Explore, Notifications, Profile
- **Deep linking** — `DeepLinkRouter` singleton (`Core/Navigation/`) handles `rosemount://` URLs and push notification routing
- **Persistence** — SwiftData (`CachedStatus`, `CachedActor`) for the local timeline cache; Keychain for tokens and E2E keys
- **Background work** — `BGTaskScheduler` with identifiers `com.rosemount.background.refresh` and `com.rosemount.background.sync`
- **Crash reporting** — MetricKit; no third-party analytics SDKs
- **Concurrency** — Swift strict concurrency (`SWIFT_STRICT_CONCURRENCY = complete`), all view models are `@MainActor`

---

## Project Structure

```
Rosemount/
├── App/            # Entry point (RosemountApp), AppCoordinator, Info.plist, entitlements
├── Core/           # Platform and service layer (no UI)
│   ├── ActivityPub/    # HTTP signatures (Ed25519/X25519), WebFinger, NodeInfo, JSON-LD models
│   ├── Auth/           # AuthManager, OAuth credential lifecycle, Keychain, BiometricAuth
│   ├── Crypto/         # Double Ratchet E2E encryption (Curve25519 + AES-GCM via CryptoKit)
│   ├── Mastodon/       # Mastodon REST API v1/v2 client + OAuth
│   ├── Navigation/     # DeepLinkRouter
│   ├── Notifications/  # PushNotificationService (APNs + Mastodon Web Push)
│   ├── Offline/        # NetworkMonitor, BackgroundSyncService, draft queue
│   ├── Pixelfed/       # Pixelfed REST API client + OAuth
│   ├── Stories/        # RosemountStory models + StoriesAPIClient
│   ├── VoiceRooms/     # VoiceAudioEngine (AVAudioEngine), WebRTCSignalingClient
│   ├── WebRTC/         # WebRTCAudioSession (AVAudioSession .voiceChat)
│   └── ...             # Communities, Events, Location, Rosemount, Scheduled, Analytics
├── Features/       # SwiftUI feature modules (one folder per screen/flow)
│   └── ...             # Feed, Stories, Communities, Events, Photos, Messaging, VoiceRooms,
│                       # Explore, Notifications, Profile, Onboarding, Settings, Compose,
│                       # Location, Polls, Scheduled, Analytics, Accessibility
├── Shared/         # Reusable SwiftUI components (PostCardView, AvatarView, etc.) + SwiftData models
├── Resources/      # Assets.xcassets, Localizable.strings, app icons
├── Tests/          # XCTest unit test suite
├── fastlane/       # Build automation (Fastfile, Matchfile, Snapfile, Deliverfile, metadata/)
├── AppStore/       # SUBMISSION_GUIDE.md, PrivacyManifest.xcprivacy
├── project.yml     # XcodeGen project definition
└── .env.example    # Required environment variable template
```

---

## Getting Started

**Prerequisites**

| Tool | Version |
|---|---|
| Xcode | 15.0+ |
| macOS | Sonoma or later |
| Ruby | System or rbenv |
| XcodeGen | `brew install xcodegen` |

**Setup**

```bash
# 1. Clone
git clone https://github.com/xozai/Rosemount.git
cd Rosemount

# 2. Install Ruby dependencies (fastlane)
bundle install

# 3. Generate the Xcode project
xcodegen generate

# 4. Configure environment variables
cp .env.example .env
# Edit .env and fill in the required values (see below)

# 5. Sync signing certificates
bundle exec fastlane certs

# 6. Open in Xcode and run
open Rosemount.xcodeproj
```

**Required environment variables** (see `.env.example` for the full list):

| Variable | Purpose |
|---|---|
| `APPLE_ID` | Your Apple ID email |
| `APP_STORE_CONNECT_TEAM_ID` | 10-character Apple Team ID |
| `MATCH_GIT_URL` | Private Git repo for encrypted certificates |
| `MATCH_PASSWORD` | Passphrase to decrypt the match repo |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | App Store Connect API issuer UUID |
| `APP_STORE_CONNECT_API_KEY_PATH` | Local path to the `.p8` key file |

---

## Building & Testing

| Command | Description |
|---|---|
| `bundle exec fastlane test` | Run the XCTest suite |
| `bundle exec fastlane beta` | Build and upload to TestFlight |
| `bundle exec fastlane screenshots` | Capture App Store screenshots |
| `bundle exec fastlane release version:1.0.0` | Full App Store submission |

For manual archiving:

```bash
xcodebuild archive \
  -scheme Rosemount \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Rosemount.xcarchive
```

See [AppStore/SUBMISSION_GUIDE.md](./AppStore/SUBMISSION_GUIDE.md) for the complete submission checklist.

---

## Encryption

**Direct Messages** use the Double Ratchet protocol (inspired by Signal): Curve25519 for key agreement and AES-GCM for symmetric encryption, implemented entirely with Apple's CryptoKit (`Core/Crypto/`). Keys are stored in the Keychain; no plaintext message content ever leaves the device unencrypted.

**ActivityPub federation** uses Ed25519 HTTP signatures (X25519 for key exchange) on all outbound `POST` requests to remote inboxes, per the ActivityPub and HTTP Signatures specifications (`Core/ActivityPub/Signatures/`).

All cryptography qualifies under the EAR 740.17(b) mass-market exemption. `ITSAppUsesNonExemptEncryption = false`; no ERN is required.

---

## Contributing

1. Open an issue before starting significant work
2. Branch from `main` and submit a PR against `main`
3. Follow existing code style: SwiftUI views, `@Observable` view models, `@MainActor` isolation
4. Do not introduce third-party package dependencies (SPM/CocoaPods/Carthage) without prior discussion
5. All user-facing strings must use `String(localized:)` with a key in `Resources/Localizable.strings`

For the full technical specification and design rationale, see [PROMPT.md](./PROMPT.md).

---

## License

See [LICENSE](./LICENSE).
