# Rosemount — Native iOS ActivityPub Community Social App
## Complete Build Prompt & Specification

---

## Overview

Build **Rosemount**, a native iOS social networking application centered on tight-knit communities.
The app is designed for groups like high school reunion classes, youth sports leagues, religious
congregations, neighborhood associations, and hobby clubs. It is built on the
[ActivityPub](https://www.w3.org/TR/activitypub/) protocol, enabling full federation and
interoperability with Mastodon, Pixelfed, and other ActivityPub-compatible platforms.

---

## Platform & Technical Requirements

| Attribute | Value |
|---|---|
| Platform | Native iOS |
| Language | Swift 5.10 |
| UI Framework | SwiftUI (primary), UIKit (where SwiftUI lacks API coverage) |
| Minimum iOS | 17.0 |
| Architecture | MVVM + Coordinator pattern |
| Networking | `URLSession` + `async/await` + `Combine` |
| Local Database | SwiftData |
| Protocol | ActivityPub (W3C Recommendation) |
| Auth | OAuth 2.0 via `ASWebAuthenticationSession` |
| Encryption | CryptoKit (HTTP Signatures), Signal Protocol (DMs) |
| Media | `PhotosUI`, `AVFoundation` |
| Maps | MapKit + CoreLocation |
| Push Notifications | Apple Push Notification service (APNs) |
| Testing | XCTest + Swift Testing |

---

## Project Structure

```
Rosemount/
├── App/
│   ├── RosemountApp.swift           # App entry point (@main)
│   └── AppCoordinator.swift         # Root navigation coordinator
├── Core/
│   ├── ActivityPub/
│   │   ├── Models/                  # AP JSON-LD types (Actor, Note, Activity, etc.)
│   │   ├── Client/                  # Inbox/Outbox HTTP client
│   │   ├── WebFinger/               # WebFinger discovery
│   │   └── Signatures/              # HTTP Signature signing & verification
│   ├── Mastodon/
│   │   ├── MastodonAPIClient.swift  # REST client for Mastodon v1/v2 API
│   │   └── MastodonOAuth.swift      # Mastodon OAuth flow
│   ├── Pixelfed/
│   │   ├── PixelfedAPIClient.swift  # REST client for Pixelfed API
│   │   └── PixelfedOAuth.swift      # Pixelfed OAuth flow
│   └── Auth/
│       ├── AuthManager.swift        # Token lifecycle, Keychain storage
│       └── BiometricAuth.swift      # Face ID / Touch ID
├── Features/
│   ├── Onboarding/                  # Registration, login, instance picker
│   ├── Feed/                        # Home, Local, Federated timelines
│   ├── Communities/                 # Group creation, management, discovery
│   ├── Photos/                      # Photo posts, editing, media picker
│   ├── Messaging/                   # DMs, group chats, voice notes
│   ├── Location/                    # Live sharing, place attach, map view
│   ├── Profile/                     # User profile, followers/following
│   ├── Notifications/               # Push + in-app notification center
│   ├── Explore/                     # Trending, hashtags, people, communities
│   ├── Events/                      # Community events and RSVPs
│   └── Settings/                   # Account, privacy, notifications, instance
├── Shared/
│   ├── Components/                  # Reusable SwiftUI views (PostCard, AvatarView, etc.)
│   ├── Extensions/                  # Swift standard library extensions
│   └── Utilities/                   # Date formatting, image caching, etc.
└── Resources/
    ├── Assets.xcassets
    └── Localizable.xcstrings
```

---

## Authentication & Identity

### Sign-In Methods

1. **Sign in with Mastodon**
   - User enters their Mastodon instance URL (e.g., `mastodon.social`)
   - App registers as an OAuth client on that instance dynamically via `/api/v1/apps`
   - OAuth 2.0 authorization code flow via `ASWebAuthenticationSession`
   - Stores access token in Keychain tagged to the account handle

2. **Sign in with Pixelfed**
   - Same OAuth 2.0 flow adapted for Pixelfed's API
   - Pixelfed instance URL entry with instance auto-detection

3. **Native Rosemount Registration**
   - Username selection → email verification → password
   - Creates an ActivityPub `Person` actor at `@username@rosemount.social`
   - Supports self-hosted instances with custom domain

4. **Biometric Unlock**
   - Face ID / Touch ID to unlock app after background (not for login)
   - Fallback to PIN code

### Session Management
- Refresh token rotation
- Multiple account support (account switcher)
- Sign-out revokes token on server

---

## ActivityPub Protocol Implementation

### Actor Model
- Implement `Person` Actor type with all required fields:
  `id`, `type`, `preferredUsername`, `inbox`, `outbox`, `followers`, `following`,
  `publicKey` (RSA 2048-bit or Ed25519), `icon`, `image`, `summary`
- Expose Actor JSON-LD at `https://rosemount.social/users/:username`

### WebFinger
- Implement WebFinger (`/.well-known/webfinger`) for account discovery
- Resolve remote handles: `@user@instance.social` → Actor JSON-LD URL
- Cache resolved actors in SwiftData with TTL

### Inbox & Outbox
- **Outbox:** Paginated ordered collection of the user's activities
- **Inbox:** Receive and process incoming activities:
  - `Create` (new post/note)
  - `Follow` / `Accept` / `Reject`
  - `Like` (EmojiReact extension for reactions)
  - `Announce` (boost/reblog)
  - `Delete`
  - `Update`
  - `Undo` (undo follow, like, boost)

### HTTP Signatures
- Sign all outgoing `POST` requests to remote inboxes with the actor's private key
- Verify incoming request signatures before processing
- Use `Digest` header for body integrity

### NodeInfo
- Expose `/.well-known/nodeinfo` and `/nodeinfo/2.1` for server metadata
- Report software name (`rosemount`), version, and user counts

---

## Mastodon Interoperability

- **Follow federation:** Follow any `@user@mastodon.social` handle from within Rosemount
- **Timeline federation:** Posts from followed Mastodon accounts appear in Home timeline
- **Boosting:** Rosemount boosts federate as Mastodon-compatible `Announce` activities
- **Mentions:** `@user@instance` mentions render as tappable profile links
- **Hashtags:** Hashtag posts federate; Mastodon users can find Rosemount posts via hashtags
- **Media:** Image/video attachments federate as `Image`/`Video` AP objects
- **Content Warnings:** Mastodon `sensitive`/`spoiler_text` fields respected and displayed
- **Polls:** Mastodon-compatible `Question` AP type for polls

---

## Pixelfed Interoperability

- **Photo federation:** Rosemount photo posts use `Image` AP type compatible with Pixelfed
- **Follow cross-platform:** Follow Pixelfed accounts; their photos appear in feed
- **Multi-image albums:** `OrderedCollectionPage` of `Image` objects for carousel posts
- **Alt-text:** `name` field on `Image` objects synced with Pixelfed alt-text
- **Like/Boost:** Federate correctly to Pixelfed

---

## Community Groups (Core Differentiator)

### Group Actor
- Implement ActivityPub `Group` actor type for each community
- Group Actor ID: `https://rosemount.social/communities/:slug`
- Posts tagged to a group are `cc`'d to the Group's followers collection

### Community Features
- **Create a Community:** Name, description, avatar, banner, public or invite-only
- **Invite Members:** By `@handle`, email, or shareable QR code / link
- **Community Feed:** Posts scoped to the group, chronological
- **Roles:**
  - `Admin` — full control, can delete community
  - `Moderator` — remove posts, remove members
  - `Member` — post and interact
- **Pinned Announcements:** Admins pin up to 5 posts at the top of the community feed
- **Community Directory:** Discover and join public communities; search by name/interest
- **Member Directory:** Searchable list of community members with follow button

---

## Photo Sharing

- **Compose:** Camera capture (AVFoundation) or photo library picker (`PhotosUI`)
- **Multi-photo posts:** Carousel of up to 10 images per post
- **Editing tools:** Crop, rotate, brightness, contrast, saturation, built-in filters
- **Alt-text:** Required field for each image (accessibility); prefilled by on-device ML caption suggestion (`Vision` framework)
- **Captions:** Rich text with `@mentions`, `#hashtags`, URLs
- **Visibility:** Public, Followers-only, Community-only, Direct
- **ActivityPub:** Published as `Create(Note)` with `attachment` array of `Image` objects
- **Pixelfed-compatible:** Media format and metadata match Pixelfed conventions
- **Caching:** `NSCache` (in-memory) + disk cache via `URLCache`; progressive JPEG loading

---

## Messaging (Direct Messages)

### Architecture
- E2E encrypted using Signal Protocol (Double Ratchet)
- Server stores only ciphertext; keys never leave device
- WebSocket connection for real-time delivery

### DM Features
- **1-on-1 Conversations:** Threaded message view, newest at bottom
- **Group DMs:** Up to 50 participants; named group chat
- **Media in DMs:** Photos, videos, voice notes (up to 2 min), documents (PDF)
- **Read receipts:** Double-check marks (delivered / seen)
- **Typing indicators:** Animated dots
- **Message reactions:** Tap-and-hold for emoji reaction on individual messages
- **Disappearing messages:** Optional 24h / 7d auto-delete per conversation
- **ActivityPub:** Use `Direct` audience visibility for federation; unencrypted DMs to non-Rosemount AP users

---

## Location Sharing

### Privacy-First Design
- Precise GPS coordinates are **never stored on the server**
- Coordinates snapped to a ~100m grid before transmission
- All location features are opt-in, off by default

### Features
- **Live Location Sharing:** Share approximate location with selected followers or community for a set duration (1h / 4h / until turned off)
- **Share a Place:** Attach a named POI (via MapKit) to a post or DM
- **Location on Posts:** Optional "neighborhood-level" location tag (city district, not street)
- **Community Map View:** Map showing members who are currently sharing their location within the community
- **Privacy Controls:** Per-share audience selection; revoke at any time

---

## Social Graph

- **Follow / Unfollow:** Local and federated (AP `Follow` / `Undo Follow`)
- **Follow Requests:** Private accounts approve/reject incoming follows
- **Follower / Following Lists:** With remote instance badge on handles
- **Mute:** Hide posts from a user (local only, not federated)
- **Block:** Remove and prevent interactions; sends AP `Block` activity
- **Suggested Connections:** Mutual follows, same community members, similar interests
- **Lists:** Organize follows into named lists for filtered timelines

---

## Feed & Discovery

### Timelines
| Timeline | Content |
|---|---|
| Home | Posts from follows + community posts, chronological |
| Community | Posts scoped to a specific community |
| Local | Posts from all Rosemount instance users |
| Federated | Posts from the full fediverse (opt-in; toggle in settings) |

### Explore Tab
- Trending posts (by engagement in last 24h)
- Trending hashtags
- People to follow (suggested accounts)
- Community discovery
- Hashtag search
- Full-text search (posts, accounts, communities)

### Hashtags
- Follow hashtags — posts appear in Home timeline
- Hashtag pages show all posts with that tag (local + federated)

---

## Notifications

### Push (APNs)
- New follower
- Follow request (for private accounts)
- Post liked
- Post boosted/reboosted
- New mention
- New DM
- Community invitation
- Community announcement pinned
- Event RSVP reminder

### In-App Notification Center
- Grouped by type (Interactions, Messages, Communities, System)
- Mark all as read
- Deep-link to relevant content on tap

### Settings
- Per-type push toggle
- Quiet hours (e.g., silence 10 PM – 8 AM)
- Notification badge count on tab bar icon

---

## Complementary Features

### Events
- Create a community event: title, date/time, location (address or MapKit POI), description, banner image
- RSVP: Going / Interested / Not Going
- Event posts federate as ActivityPub `Event` type (compatible with Mobilizon)
- Event reminders via push notification (1 day and 1 hour before)
- Attendee list visible to community members

### Polls
- Attach a poll to any post: up to 4 options, custom expiry (1h – 7d)
- Single or multiple choice
- Results revealed after voting or after expiry
- Mastodon-compatible `Question` AP type

### Stories
- 24-hour ephemeral photo/video stories (up to 15 seconds per clip)
- Visible to followers or community members
- View count and viewer list for your own stories
- React to a story with an emoji (sends DM)
- Stories do not federate outside Rosemount (local feature)

### Voice Rooms
- Ephemeral audio rooms within a community (admin or moderator creates)
- Speaker / Listener roles; raise hand to speak
- Up to 200 participants
- Rooms auto-close when the creator leaves or after 4 hours
- Built with WebRTC

### Bookmarks
- Save any post privately
- Organized into named bookmark collections
- Not visible to other users or federated

### Scheduled Posts
- Schedule a post for a specific date and time
- Manage scheduled posts queue (edit, delete, post now)

### Content Warnings
- Attach a CW/spoiler label to any post
- Post body collapsed by default; tap to expand
- Mastodon-compatible `sensitive` and `spoiler_text` fields

### Emoji Reactions
- Tap-and-hold a post to react with an emoji (❤️ 🔥 😂 😢 👏 🙌)
- Reaction counts shown below post
- Uses `EmojiReact` AP extension (Misskey/Pleroma compatible)

### Thread View
- Expand any post into its full reply thread
- Collapse/expand branches
- Load more replies on demand

### Offline Mode
- Read cached timeline, communities, and DMs while offline
- Compose posts and queue for send when connection restores
- Background sync when app returns to foreground

### Community Analytics (Admins Only)
- Posts per week trend chart
- Active members count (posted or reacted in last 30 days)
- Top posts in community (by engagement)
- Member growth over time

### Accessibility
- Full Dynamic Type support (all text scales with system font size)
- VoiceOver labels on all interactive elements
- High-contrast mode
- Reduce Motion support (disable parallax, animated transitions)
- Haptic feedback on key interactions

---

## Privacy & Safety

- **Privacy settings per post:** Public, Followers-only, Community, Direct
- **Account privacy:** Public or Private (followers-only, requires approval)
- **Data export:** Download archive of posts, media, follows (ActivityPub-standard format)
- **Account deletion:** Sends AP `Delete(Person)` activity to federate removal
- **Report:** Report posts or accounts; routes to instance moderators
- **Content filtering:** Keyword mute (hide posts containing specific words/phrases)
- **NSFW media:** Blur sensitive media by default (toggle in settings)
- **Two-factor authentication (2FA):** TOTP-based (for native accounts)

---

## Onboarding Flow

1. **Welcome screen** — App value proposition; "Join Rosemount" / "Sign in"
2. **Sign-in method picker** — Mastodon / Pixelfed / Create Rosemount account
3. **Instance entry** (Mastodon/Pixelfed) — URL field with popular instance suggestions
4. **OAuth consent** — Redirect to instance for authorization
5. **Profile setup** — Display name, avatar, bio (pre-filled from federated account if available)
6. **Find communities** — Browse and join public communities; invite code entry
7. **Find people** — Import follows from federated account; suggested accounts
8. **Notifications permission** — APNs prompt with explanation
9. **Location permission** — CoreLocation prompt; explain opt-in nature
10. **Home feed** — Onboarding complete

---

## Implementation Phases

### Phase 1 — Foundation
- Xcode project setup with SwiftData, SwiftUI navigation
- ActivityPub core library (models, HTTP client, WebFinger, HTTP Signatures)
- Mastodon OAuth login + token storage
- Pixelfed OAuth login
- Basic Home timeline (fetch and display posts)
- Post composer (text only)

### Phase 2 — Core Social
- Photo posts with multi-image support and editing
- Follow / unfollow (local + federated)
- Profile screens (own + others)
- Notifications (push + in-app)
- Direct messages (1-on-1, unencrypted first; E2E in Phase 4)

### Phase 3 — Communities
- Community creation and management
- Community feed
- Invite system (handle, link, QR code)
- Member directory and roles
- Pinned announcements

### Phase 4 — Enhanced Features
- E2E encrypted DMs (Signal Protocol)
- Location sharing and community map
- Events with RSVP
- Polls
- Stories
- Emoji reactions

### Phase 5 — Polish & Scale
- Voice rooms (WebRTC)
- Offline mode and background sync
- Scheduled posts
- Community analytics
- Accessibility audit
- Performance profiling and optimization
- App Store submission

---

## API Surface (Backend Requirements)

The Rosemount server must expose:

| Endpoint | Description |
|---|---|
| `GET /.well-known/webfinger` | WebFinger discovery |
| `GET /.well-known/nodeinfo` | NodeInfo redirect |
| `GET /nodeinfo/2.1` | Server metadata |
| `GET /users/:username` | Actor JSON-LD |
| `POST /users/:username/inbox` | Receive AP activities |
| `GET /users/:username/outbox` | Paginated activities |
| `GET /users/:username/followers` | Followers collection |
| `GET /users/:username/following` | Following collection |
| `GET /communities/:slug` | Community Group Actor |
| `POST /communities/:slug/inbox` | Community inbox |
| `POST /api/v1/auth/register` | Native registration |
| `POST /api/v1/statuses` | Create post |
| `GET /api/v1/timelines/home` | Home timeline |
| `GET /api/v1/timelines/local` | Local timeline |
| `GET /api/v1/timelines/public` | Federated timeline |
| `GET /api/v1/notifications` | Notifications |
| `GET /api/v1/conversations` | DM threads |
| `POST /api/v1/media` | Upload media |
| `GET /api/v1/search` | Full-text search |
| `GET /api/v1/communities` | Community directory |
| `WS /api/v1/streaming` | WebSocket streaming |

The Mastodon-compatible REST API layer allows existing Mastodon client libraries to work with
Rosemount's backend, reducing implementation effort.

---

## Design Guidelines

- **Design system:** SF Symbols throughout; no third-party icon libraries
- **Typography:** SF Pro; Dynamic Type scaling for all text
- **Color:** Adaptive light/dark mode; system semantic colors where possible
- **Spacing:** 8pt grid
- **Navigation:** Tab bar (5 tabs: Home, Communities, Compose, Notifications, Profile)
- **Compose button:** Floating action button in center tab bar position
- **Post card:** Avatar, display name, handle, timestamp, content, media, action bar (Like, Boost, Reply, Share)
- **Community card:** Banner image, name, member count, join/joined button
- **Animations:** Respect `Reduce Motion`; subtle spring animations for interactions

---

## Testing Requirements

- Unit tests for all ActivityPub model encoding/decoding (XCTest)
- Unit tests for WebFinger resolution and HTTP Signature generation/verification
- UI tests for critical flows: login, compose post, follow user, create community (Swift Testing)
- Integration tests against a local Mastodon/Pixelfed instance (Docker Compose)
- Snapshot tests for key SwiftUI components

---

*This document is the authoritative specification for the Rosemount iOS application.*
*All implementation decisions should reference this prompt.*
