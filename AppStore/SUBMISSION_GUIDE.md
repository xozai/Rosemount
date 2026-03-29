# Rosemount — App Store Submission Guide

> Step-by-step guide for submitting Rosemount 1.0 to the Apple App Store.
> Follow sections in order. Check off each item as it is completed.

---

## 1. Prerequisites

- [ ] Apple Developer Program membership active (paid, $99/year)
- [ ] Xcode 15.4+ installed on macOS Sonoma or later
- [ ] Valid distribution certificate in Keychain (`Apple Distribution: …`)
- [ ] App Store provisioning profile for `com.rosemount.ios` downloaded
- [ ] App Store Connect record created for "Rosemount" at appstoreconnect.apple.com
- [ ] fastlane installed: `gem install fastlane` (optional but recommended)

---

## 2. Codebase Checklist

- [ ] All Swift files compile with 0 errors and 0 warnings
- [ ] `App/Info.plist` contains `ITSAppUsesNonExemptEncryption = false`
- [ ] `CFBundleVersion` (build number) is bumped for each upload
- [ ] `CFBundleShortVersionString` (marketing version) is `1.0.0`
- [ ] No `DEBUG`-only code paths reachable in a Release build
- [ ] `NSAllowsArbitraryLoads` is `false` in `NSAppTransportSecurity`
- [ ] All 6 privacy usage description strings present in Info.plist

### Required Info.plist Keys

| Key | Description |
|---|---|
| `NSCameraUsageDescription` | Camera access for posts/stories |
| `NSPhotoLibraryUsageDescription` | Photo library for posts/profiles |
| `NSPhotoLibraryAddUsageDescription` | Saving images to library |
| `NSLocationWhenInUseUsageDescription` | Location tagging on posts |
| `NSMicrophoneUsageDescription` | Voice Rooms audio |
| `NSFaceIDUsageDescription` | Biometric app lock |

---

## 3. Build & Archive

### Option A — Xcode GUI
1. Set scheme to **Rosemount** and destination to **Any iOS Device (arm64)**
2. `Product → Archive`
3. After archive: **Distribute App → App Store Connect → Upload**
4. Choose "Automatically manage signing" or select the manual profile

### Option B — Command Line
```bash
# Build and archive
xcodebuild archive \
  -scheme Rosemount \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath build/Rosemount.xcarchive

# Export IPA
xcodebuild -exportArchive \
  -archivePath build/Rosemount.xcarchive \
  -exportOptionsPlist ExportOptions.plist \
  -exportPath build/

# Upload with altool (deprecated but still works)
xcrun altool --upload-app \
  --type ios \
  --file build/Rosemount.ipa \
  --apiKey YOUR_ASC_API_KEY \
  --apiIssuer YOUR_ISSUER_ID
```

### Option C — fastlane deliver
```bash
cd AppStore/fastlane
bundle exec fastlane deliver --skip_binary_upload   # metadata only
bundle exec fastlane deliver                        # full submission
```
See `AppStore/fastlane/Deliverfile` for configuration.

---

## 4. App Store Connect — Metadata

Copy content from `AppStore/metadata.md`:

- [ ] App Name: **Rosemount**
- [ ] Subtitle: **Community Social on the Open Web**
- [ ] Description (paste from metadata.md)
- [ ] Keywords (paste from metadata.md — max 100 chars)
- [ ] Promotional Text (paste from metadata.md)
- [ ] Support URL: `https://rosemount.social/support`
- [ ] Marketing URL: `https://rosemount.social`
- [ ] Privacy Policy URL: `https://rosemount.social/privacy`
- [ ] Copyright: `© 2026 Rosemount Social, Inc.`
- [ ] Age Rating questionnaire completed (result: **12+**)

---

## 5. App Icon

Required file: `Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png`

- [ ] 1024 × 1024 px PNG (already present)
- [ ] No rounded corners (Xcode applies automatically)
- [ ] No alpha channel / transparency
- [ ] No status bar, notch, or device frame
- [ ] Minimum contrast — readable at small sizes

To regenerate all icon sizes from the 1024px source:
```bash
chmod +x AppStore/generate_icon_placeholder.sh
./AppStore/generate_icon_placeholder.sh
```
Requires: `brew install imagemagick`

---

## 6. Screenshots

**Minimum:** 3 screenshots for iPhone 6.7" (1290 × 2796 px)

| # | Screen | Content |
|---|---|---|
| 1 | Home Timeline | Feed with several posts visible |
| 2 | Community | A community feed with members and posts |
| 3 | Direct Messages | An encrypted chat thread |
| 4 | Explore | Trending hashtags list |
| 5 | Profile | Profile header with stats and posts grid |

### Capture Process (Simulator)
1. Run on iPhone 15 Pro Max simulator (6.7")
2. `Simulator → File → New Screenshot` or `Cmd+S`
3. Crop to exact size with Preview or `sips`

### Framed Screenshots (Optional)
Use [fastlane snapshot](https://docs.fastlane.tools/actions/snapshot/) +
[fastlane frameit](https://docs.fastlane.tools/actions/frameit/) to generate
device-framed marketing screenshots automatically.

---

## 7. App Review Notes

The following review notes are pre-populated in `AppStore/fastlane/Deliverfile`.
Copy into the "Notes" field in App Store Connect if submitting manually:

```
To review the app without a live Mastodon server:

1. Launch the app and tap "Sign in with Mastodon"
2. In the "Your Instance" field, type exactly: rosemount-review
3. Tap "Continue"

This activates Demo Mode. All tabs are fully navigable with sample content.
No network connection is required.

Voice Rooms require a WebSocket server. In demo mode, tapping Join shows
an "Unavailable" alert — this is expected behaviour.

Contact: support@rosemount.social
```

---

## 8. App Encryption Declaration

- [ ] `ITSAppUsesNonExemptEncryption = false` in `Info.plist` ✓
- [ ] No separate ERN (Encryption Registration Number) required

**Rationale:** Rosemount uses CryptoKit for:
- HTTP Signatures (ActivityPub federation): Ed25519, X25519
- E2E DM key agreement: X25519, HKDF-SHA256
- E2E DM encryption: AES-GCM

All algorithms qualify under EAR 740.17(b) — mass-market cryptography exemption.
Apple accepts `ITSAppUsesNonExemptEncryption = false` for this category.

---

## 9. Entitlements

Verify the following entitlements are in `Rosemount.entitlements`:

| Entitlement | Value | Required For |
|---|---|---|
| `com.apple.developer.associated-domains` | `applinks:rosemount.social` | Universal Links |
| `com.apple.security.application-groups` | (optional) | Shared app group |
| `keychain-access-groups` | `com.rosemount.app` | Keychain sharing |
| `aps-environment` | `production` | APNs push notifications |

---

## 10. TestFlight (Recommended Before Submission)

1. Upload build to App Store Connect
2. Add internal testers (team members)
3. Complete beta testing checklist:
   - [ ] Sign in with Mastodon (live instance)
   - [ ] Sign in via Demo Mode ("rosemount-review")
   - [ ] Post a status
   - [ ] Send a DM
   - [ ] Join a Voice Room (or verify graceful failure)
   - [ ] Test offline mode (airplane mode)
   - [ ] Test Face ID lock
   - [ ] Test push notifications
   - [ ] Test deep links (`rosemount://profile/`, `rosemount://status/`)

---

## 11. Final Submission Checklist

- [ ] Build uploaded and processed in App Store Connect
- [ ] All metadata fields completed
- [ ] Screenshots uploaded for all required device sizes
- [ ] Age rating questionnaire completed
- [ ] App Review notes filled in
- [ ] Privacy Policy URL accessible (returns HTTP 200)
- [ ] Support URL accessible (returns HTTP 200)
- [ ] Marketing URL accessible (returns HTTP 200)
- [ ] "Submit for Review" clicked in App Store Connect
- [ ] Review set to **Manual Release** (release at your discretion after approval)

---

## 12. Post-Approval

- [ ] Set release date or click **Release This Version** in App Store Connect
- [ ] Monitor crash reports in Xcode Organizer / MetricKit dashboard
- [ ] Monitor reviews in App Store Connect
- [ ] Tag the release commit: `git tag v1.0.0 && git push origin v1.0.0`

---

## Useful Links

| Resource | URL |
|---|---|
| App Store Connect | https://appstoreconnect.apple.com |
| Apple Developer Portal | https://developer.apple.com/account |
| Human Interface Guidelines | https://developer.apple.com/design/human-interface-guidelines |
| App Store Review Guidelines | https://developer.apple.com/app-store/review/guidelines |
| fastlane deliver docs | https://docs.fastlane.tools/actions/deliver |
| App Store screenshot specs | https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications |
