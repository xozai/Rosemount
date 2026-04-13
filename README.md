# Rosemount

> Community social on the open web

![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue) ![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange) ![License](https://img.shields.io/badge/license-See%20LICENSE-lightgrey)

A native iOS social networking app built on the ActivityPub protocol, with full interoperability with Mastodon and Pixelfed.

---

![Platform](https://img.shields.io/badge/platform-iOS%2017%2B-blue)
![Language](https://img.shields.io/badge/swift-5.10-orange)
![License](https://img.shields.io/badge/license-Apache%202.0-green)
![Status](https://img.shields.io/badge/status-Active%20Development-brightgreen)

<!-- Add simulator screenshots here -->

## What is Rosemount?

Rosemount is a community-first social network built on the [ActivityPub](https://www.w3.org/TR/activitypub/)
W3C standard — the same open protocol that powers Mastodon, Pixelfed, and thousands of other
servers across the fediverse. Rather than targeting the global public square, Rosemount is
designed for the groups that matter most in daily life: high school reunion groups, youth sports
leagues, religious congregations, neighborhood associations, and hobby clubs.

Because Rosemount speaks ActivityPub natively, your account federates freely with any Mastodon
or Pixelfed instance. You can follow friends on other servers, boost their posts, and reply to
them — all from within Rosemount. Your data lives on a server you choose (or self-host), never
locked into a proprietary platform.

Location features are privacy-first by design: precise coordinates are never stored, and any
shared position is grid-snapped to approximately 100 meters. The app is distributed on the
Apple App Store and is fully open source.

## Features

### Core Social
- Chronological home timeline with home, local, and federated feed modes
- Rich post composer with content warnings, visibility levels, and character counter
- Boosts, favourites, emoji reactions, bookmarks, and threaded replies
- Mastodon-compatible polls attached to posts
- Draft saving and scheduled posts
- Offline read mode with background sync queue

### Communities
- Create public or private named groups scoped to an ActivityPub `Group` actor
- Roles: Admin, Moderator, Member — each with distinct permissions
- Invite members by handle, shareable link, or QR code
- Pinned announcements at the top of the community feed
- Searchable member directory per community
- Community analytics for admins (posts per week, active members)

### Messaging
- End-to-end encrypted direct messages (Double Ratchet / Signal Protocol)
- Group DMs up to 50 participants
- Voice notes, photo sharing, and file attachments in DMs
- Read receipts and typing indicators over WebSocket
- ActivityPub `Direct` visibility for federated DM interoperability

### Media
- Multi-photo posts up to 10 images with carousel display
- In-app editing: crop, brightness, contrast, filters
- Required alt text (accessibility descriptions) on every image before posting
- Federated as ActivityPub `Image` objects — fully compatible with Pixelfed
- Local thumbnail cache (NSCache + disk fallback)

### Location
- Opt-in live location sharing (1 h / 4 h / until turned off)
- Attach a named place (MapKit point of interest) to any post
- Community map view showing members who have opted in
- Privacy guarantee: coordinates snapped to ~100 m grid, never stored precisely

### Discovery
- Explore tab: trending posts, hashtags, and public communities
- Hashtag following and per-hashtag timelines
- Full-text search across accounts, statuses, and hashtags
- Federated and local public timelines (opt-in)

### Notifications
- Push notifications via APNs for follows, likes, boosts, mentions, and DMs
- In-app notification centre with filter tabs
- Notification grouping by type and community
- Quiet hours setting

### Coming Soon
- **Voice Rooms** — Ephemeral live audio rooms for communities (WebRTC, Clubhouse-style).
  Currently gated behind a Coming Soon placeholder while the peer-connection layer ships.

## Architecture

| Concern | Approach |
|---|---|
| UI pattern | MVVM — `@Observable @MainActor` ViewModels, SwiftUI views |
| API clients | `actor`-isolated — thread-safe by construction |
| Concurrency | `async/await` throughout; `SWIFT_STRICT_CONCURRENCY: complete` |
| ActivityPub | Custom HTTP Signatures (CryptoKit), WebFinger discovery, Inbox/Outbox |
| Storage | SwiftData (timeline cache), Keychain (OAuth tokens), `OfflineStore` (drafts & action queue) |
| Media | PhotosUI picker, AVFoundation (voice notes), NSCache + disk thumbnail cache |
| Push | APNs via `UserNotifications`; relay server bridges to Mastodon Web Push |
| Encryption | CryptoKit (HTTP Signatures), Double Ratchet (DMs) |
| Project generation | [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `project.yml` is the source of truth |

## Getting Started

**Prerequisites:** macOS 14 (Sonoma) or later, Xcode 16+, [Homebrew](https://brew.sh)

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Clone and switch to the development branch
git clone https://github.com/xozai/Rosemount.git
cd Rosemount
git checkout claude/ios-activitypub-social-app-k9seL
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

# 4. Open and run
open Rosemount.xcodeproj
# Select an iPhone 15 simulator, then press ⌘R
```

**App Review / Demo mode:** On the sign-in screen, type `rosemount-review` as the instance
URL and tap any sign-in button. This activates a local-only demo account that lets you
navigate all tabs without a live server.

## Project Structure

```
Rosemount/
├── App/            # Entry point, AppCoordinator, Info.plist
├── Core/           # Protocol clients and domain logic
│   ├── ActivityPub/    # AP actor model, HTTP Signatures, WebFinger
│   ├── Auth/           # OAuth flows, Keychain, AuthManager
│   ├── Mastodon/       # Mastodon REST API client (v1/v2)
│   ├── Pixelfed/       # Pixelfed API client
│   ├── Communities/    # Community API client
│   ├── Events/         # Events & RSVP API client
│   ├── Stories/        # Stories API client
│   ├── Messaging/      # E2E message service, Double Ratchet
│   ├── Location/       # LocationManager, privacy snapping
│   ├── Notifications/  # Push registration, APNs delegate
│   ├── Offline/        # NetworkMonitor, BackgroundSyncService, OfflineStore
│   ├── Scheduled/      # Scheduled post queue
│   ├── VoiceRooms/     # WebRTC signaling, audio engine (in development)
│   └── WebRTC/         # WebRTC audio session
├── Features/       # One folder per screen or user flow
│   ├── Feed/           # Home timeline
│   ├── Communities/    # Community list, detail, compose, invite
│   ├── Compose/        # Post composer
│   ├── Messaging/      # DM conversations and thread view
│   ├── Notifications/  # Notification centre
│   ├── Profile/        # User profile, followers/following
│   ├── Photos/         # Photo feed and photo post composer
│   ├── Events/         # Event list and detail
│   ├── Stories/        # Story viewer and composer
│   ├── Explore/        # Trending, search, discovery
│   ├── Location/       # Place picker, community map
│   ├── Settings/       # Account settings, licenses, accessibility
│   ├── Onboarding/     # Sign-in and registration flow
│   └── VoiceRooms/     # Voice room UI (Coming Soon)
├── Shared/         # Reusable SwiftUI components and utilities
│   ├── Components/     # PostCardView, AvatarView, CharacterCountView, …
│   └── Extensions/     # JSONDecoder+Mastodon, Collection+Safe, …
├── Resources/      # Assets, Localizable.strings
├── AppStore/       # Submission checklist, URL health checker
└── Tests/          # Unit and integration tests
```

## Requirements

| Requirement | Version |
|---|---|
| iOS | 17.0+ |
| Xcode | 16.0+ |
| Swift | 5.10 |
| macOS (dev machine) | 14.0+ (Sonoma) |

## Contributing

Contributions are welcome. Please follow these conventions so the codebase stays consistent.

**Branches**
```
feature/<short-description>
fix/<short-description>
chore/<short-description>
docs/<short-description>
```

**Commits** — [Conventional Commits](https://www.conventionalcommits.org/) style:
```
feat: add hashtag following to explore tab
fix: handle 429 rate-limit in home timeline
chore: remove dead VoiceRoomRowView struct
docs: add Apache 2.0 license and rewrite README
```

**Code conventions**

- All ViewModels must be `@Observable @MainActor final class`
- All API clients must be `actor`-isolated
- `SWIFT_STRICT_CONCURRENCY: complete` — the project must compile without concurrency warnings
- Every user-facing string must go through `String(localized: "key")` with a matching entry
  in `Resources/Localizable.strings`
- `URL(string:)!` force-unwraps are only permitted on compile-time-verified static constants
  (e.g. `static let baseURL = URL(string: "https://example.com")!`); never on runtime data
- New UI must include `.accessibilityLabel` on icon-only interactive elements

**Running tests**
```bash
xcodegen generate
xcodebuild test \
  -scheme Rosemount \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

## License

Distributed under the Apache License 2.0. See [LICENSE](./LICENSE) for details.
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
