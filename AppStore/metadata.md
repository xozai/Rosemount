# Rosemount — App Store Connect Metadata

> Copy-paste this content into App Store Connect fields.
> Fields marked **[REQUIRED]** must be filled before submission.

---

## App Information

| Field | Value |
|---|---|
| **App Name** | Rosemount |
| **Subtitle** | Community Social on the Open Web |
| **Bundle ID** | com.rosemount.ios |
| **SKU** | ROSEMOUNT-IOS-001 |
| **Primary Category** | Social Networking |
| **Secondary Category** | Lifestyle |
| **Age Rating** | 12+ |
| **Copyright** | © 2026 Rosemount Social, Inc. |

---

## Version Information

| Field | Value |
|---|---|
| **Version Number** | 1.0.0 |
| **Build Number** | 1 |
| **Minimum iOS Version** | 17.0 |

---

## App Description (4000 chars max)

```
Rosemount is a community-first social network built on the open ActivityPub standard — the same protocol that powers Mastodon, Pixelfed, and thousands of independent servers worldwide.

No algorithmic feed. No ads. No data mining. Just your communities.

COMMUNITIES
Organize around what matters — neighborhood associations, sports leagues, religious groups, and friend circles all get their own feed, events, member directory, and pinned announcements. Create public or private communities and invite members by handle or QR code.

OPEN FEDERATION
Your account works across the entire fediverse. Follow people on Mastodon, Pixelfed, Misskey, and other ActivityPub platforms directly from Rosemount. Your posts reach them; their posts reach you.

PRIVATE MESSAGING
All direct messages are end-to-end encrypted using the Double Ratchet protocol (the same cryptographic design used by Signal). Your conversations are private by default — even from Rosemount's servers.

VOICE ROOMS
Drop into live audio conversations with your community. Start an impromptu voice room or join one already in progress — no scheduling required.

STORIES
Share moments from your day as 24-hour ephemeral photos and videos visible only to your followers. Stories disappear automatically; they never live on your profile.

EVENTS
Create community events with location, description, and RSVP. Federated as ActivityPub Event objects so members on other platforms can see and attend too.

PHOTOS
A beautiful photo timeline compatible with Pixelfed. Post single images or multi-photo carousels with full alt-text support for accessibility.

MORE FEATURES
• Home, Local, and Federated timelines
• Explore tab with trending hashtags
• Polls with expiry times
• Content warnings / spoiler tags
• Emoji reactions
• Bookmarks
• Mute and block (federated)
• Offline reading mode
• Face ID / Touch ID app lock
• Dynamic Type and full VoiceOver support

OPEN SOURCE
Rosemount is open source. You can inspect the code, run your own server, and migrate your account to any ActivityPub-compatible platform at any time. Your data is yours.
```

---

## Promotional Text (170 chars max — updated without new submission)

```
Now with Voice Rooms and end-to-end encrypted DMs. Community-first social networking on the open web. Free, open source, no ads.
```

---

## Keywords (100 chars max, comma-separated)

```
social,community,fediverse,mastodon,activitypub,decentralized,privacy,local,open,pixelfed
```

---

## Support URL

```
https://rosemount.social/support
```

## Marketing URL

```
https://rosemount.social
```

## Privacy Policy URL

```
https://rosemount.social/privacy
```

---

## What's New in This Version (4000 chars max)

```
Welcome to Rosemount 1.0!

Rosemount is a community-first social network built on the open ActivityPub standard. This is our first public release for iOS.

What's included:
• Home, Local, and Federated timelines with infinite scroll
• Communities with member roles, feeds, and events
• End-to-end encrypted Direct Messages
• Voice Rooms for live audio conversations
• Stories (24-hour ephemeral posts)
• Full Mastodon and Pixelfed federation
• Explore tab with trending hashtags and search
• Face ID / Touch ID app lock
• Full VoiceOver and Dynamic Type support

We're excited to share Rosemount with the world. Feedback and contributions are welcome at rosemount.social.
```

---

## Age Rating Questionnaire

| Category | Rating |
|---|---|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Mature/Suggestive Themes | Infrequent/Mild |
| Horror/Fear Themes | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use | None |
| Gambling | None |
| **Resulting Age Rating** | **12+** |

---

## Review Notes (for App Review team)

```
To review the app without a live Mastodon server:

1. Launch the app and tap "Sign in with Mastodon"
2. In the "Your Instance" field, type exactly: rosemount-review
3. Tap "Continue"

This activates Demo Mode, which pre-populates the home timeline, communities, notifications, and profile tab with sample content. All features are fully navigable. No network connection is required for the demo.

Voice Rooms require a WebSocket server. In demo mode, attempting to join a room shows an "Unavailable" alert — this is intentional behaviour, not a bug.

For any questions, contact support@rosemount.social
```

---

## Screenshots Required

| Device | Sizes Required | Notes |
|---|---|---|
| iPhone 6.7" (Pro Max) | 1290 × 2796 px | **Required** |
| iPhone 6.5" (Plus/Max) | 1242 × 2688 px | Optional but recommended |
| iPhone 5.5" | 1242 × 2208 px | Optional |
| iPad Pro 12.9" (2nd gen+) | 2048 × 2732 px | Required if iPad supported |
| iPad Pro 12.9" (1st gen) | 2048 × 2732 px | |

**Minimum:** 3 screenshots per device. **Maximum:** 10 per device.

### Suggested Screenshot Sequence
1. Home timeline (feed with posts)
2. Community view (community feed)
3. Direct Messages (encrypted chat thread)
4. Explore / Trending hashtags
5. Profile view

---

## App Encryption

**Uses Non-Exempt Encryption:** No

CryptoKit is used for HTTP Signatures (ActivityPub federation security) and the Double Ratchet key derivation. All algorithms used (X25519, Ed25519, AES-GCM, HKDF-SHA256) fall under the EAR 740.17(b) mass-market exemption. No US export declaration is required.

`ITSAppUsesNonExemptEncryption = false` is set in Info.plist.
