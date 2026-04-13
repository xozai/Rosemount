# Rosemount — App Store Submission Steps

> A linear, top-to-bottom guide for submitting Rosemount to the Apple App Store.
> Follow every step in order. Skipping steps risks rejection.

---

## Prerequisites

Before starting, confirm you have all of the following:

| Requirement | Details |
|---|---|
| **Xcode 15.4+** | Install from the Mac App Store or developer.apple.com/xcode |
| **macOS Sonoma 14.0+** | Required for Xcode 15.4 |
| **Apple Developer Program** | Active paid membership ($99/year) at developer.apple.com/account |
| **App Store Connect access** | Admin or App Manager role on the Rosemount app record |
| **Ruby + Bundler** | `gem install bundler && bundle install` from the project root |
| **fastlane** | Installed via Bundler — `bundle exec fastlane --version` should succeed |
| **Match certificates** | Private Git repo URL set in `MATCH_GIT_URL` (see `.env.example`) |
| **App Store Connect API key** | `.p8` key file path set in `APP_STORE_CONNECT_API_KEY_PATH` |
| **`.env` populated** | Copy `.env.example` → `.env`, fill in all values |

Set environment variables before running any fastlane command:

```bash
export DEVELOPMENT_TEAM="XXXXXXXXXX"          # Your 10-character Apple Team ID
export MATCH_GIT_URL="git@github.com:you/certs.git"
export MATCH_PASSWORD="your-match-passphrase"
export APP_STORE_CONNECT_TEAM_ID="XXXXXXXXXX"
export APP_STORE_CONNECT_API_KEY_ID="ABCD123456"
export APP_STORE_CONNECT_API_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export APP_STORE_CONNECT_API_KEY_PATH="/path/to/AuthKey_ABCD123456.p8"
```

Or source them from your `.env` file:

```bash
set -a && source .env && set +a
```

---

## Step 1: Sync Certificates

Fetch the App Store distribution certificate and provisioning profile from the Match repository.

```bash
bundle exec fastlane certs
```

**What it does:** Runs `match(type: "appstore", readonly: true)` — downloads the existing
distribution certificate and provisioning profile to your Keychain and
`~/Library/MobileDevice/Provisioning Profiles/`. Does not create new certificates.

**If it fails:** Run `bundle exec fastlane setup_match` once to create the certificate and
profile, then re-run `bundle exec fastlane certs`.

---

## Step 2: Run Tests

All tests must pass before building a release binary.

```bash
bundle exec fastlane test
```

**What it does:** Runs `xcodebuild test` against the `RosemountTests` scheme on an
iPhone 16 Pro simulator. Outputs a JUnit report to `./build/test-results/report.junit`.

**Pass criteria:** `0 failures, 0 errors` in the test output.

**If tests fail:** Fix the failing tests before proceeding. Do not submit a build with
known test failures.

---

## Step 3: Capture Screenshots

Screenshots are required by App Store Connect before you can submit for review.

```bash
bundle exec fastlane screenshots
```

**What it does:**
1. Erases and resets the configured simulators to a clean state
2. Runs the `RosemountUITests` scheme, which calls `snapshot()` at key screens
3. Saves `.png` files to `fastlane/screenshots/en-US/`
4. Wraps screenshots in device frames using `frame_screenshots`

**Verify the output:**

```bash
ls fastlane/screenshots/en-US/
```

You should see `.png` files for:
- `iPhone 15 Pro Max` (1290 × 2796 px) — **required**
- `iPhone 15` (1179 × 2556 px) — **required**
- `iPad Pro (12.9-inch) (6th generation)` (2048 × 2732 px) — required if iPad is enabled

**Minimum:** At least 3 screenshots for the 6.7" iPhone size are required to submit.

**If no `.png` files appear:** Ensure the `RosemountUITests` scheme exists in the Xcode
project and contains `snapshot()` calls at the appropriate screens.

---

## Step 4: Bump Version and Build Number

### When to bump the marketing version (`MARKETING_VERSION`)

Bump `MARKETING_VERSION` (e.g. `1.0.0` → `1.0.1`) when:
- Shipping a new user-facing release to the App Store
- Fixing a bug that warrants a visible version change

```bash
bundle exec fastlane bump version:1.0.1
```

### When to bump the build number (`CURRENT_PROJECT_VERSION`)

Bump the build number for **every upload** to App Store Connect, including:
- TestFlight builds
- Re-uploads after rejection
- Builds that differ only in metadata

The `release` lane (Step 5) bumps the build number automatically.

To bump the build number manually without changing the marketing version:

```bash
# Using agvtool (requires the project to use agvtool-compatible settings)
agvtool next-version -all

# Or using fastlane directly
bundle exec fastlane run increment_build_number xcodeproj:Rosemount.xcodeproj
```

**Rule:** Every build uploaded to App Store Connect must have a build number strictly
greater than the previous upload for the same marketing version.

---

## Step 5: Archive and Upload to App Store Connect

Run the full release lane. Pass the marketing version you want to ship:

```bash
bundle exec fastlane release version:1.0.0
```

**What the `release` lane does, in order:**

1. **Guard** — verifies a `version:` argument was supplied
2. **`test`** — runs the full unit test suite (fails the lane if any test fails)
3. **`certs`** — syncs the App Store distribution certificate and profile
4. **`increment_version_number`** — sets `MARKETING_VERSION` to the supplied value
5. **`increment_build_number`** — increments `CURRENT_PROJECT_VERSION` by 1
6. **`build_app`** — archives the `Rosemount` scheme in Release configuration using the
   App Store export method and the `match AppStore social.rosemount.app` provisioning profile
7. **`deliver`** — uploads the `.ipa`, metadata, and screenshots to App Store Connect;
   calls `submit_for_review: true` to kick off App Review automatically
8. **`git_commit`** — commits the bumped version files
9. **`add_git_tag`** — tags the commit `v1.0.0`
10. **`push_to_git_remote`** — pushes the commit and tag to origin

**Output:** `./build/Rosemount.ipa` (the submitted binary)

**To skip screenshots during upload** (if you are re-uploading after a rejection):

```bash
bundle exec fastlane release version:1.0.0 skip_screenshots:true
```

---

## Step 6: App Store Connect Configuration

After the binary is processed (usually 5–30 minutes after upload), complete the
following in [App Store Connect](https://appstoreconnect.apple.com):

1. **Log in** → select **Rosemount** → **App Store** tab

2. **Version Information**
   - Verify `What's New in This Version` matches `fastlane/metadata/en-US/release_notes.txt`
   - Confirm description, subtitle, and keywords are populated from `fastlane/metadata/en-US/`

3. **Screenshots**
   - Navigate to **App Store → iOS App → Screenshots**
   - Confirm all uploaded screenshots appear for iPhone 6.7", iPhone 6.1", and iPad 12.9"
   - Drag to reorder if needed (Home Timeline first is recommended)

4. **Age Rating**
   - Navigate to **General → Age Rating**
   - Complete the questionnaire:
     - User Generated Content: **Frequent / Intense** (social posts, DMs)
     - Alcohol, Tobacco, Drugs: **None**
     - Sexual Content: **None**
     - Violence: **None**
     - Horror: **None**
   - Expected result: **12+**

5. **Pricing and Availability**
   - Set price to **Free**
   - Enable availability in all territories (or restrict as needed)

6. **App Privacy**
   - Navigate to **General → App Privacy → Edit**
   - Confirm data types match `App/PrivacyInfo.xcprivacy`:
     - **Contact Info** (name, email) — collected, linked to user
     - **User Content** (messages, photos) — collected, linked to user
     - **Location** (coarse location) — collected, linked to user, optional
     - **Identifiers** (user ID) — collected, linked to user
     - **Usage Data** (product interaction) — collected, not linked to user (MetricKit)

7. **Build Selection**
   - Under **Build**, click **+** and select the build uploaded in Step 5
   - The build must show status **Ready to Submit** (green)

---

## Step 7: App Review Notes

In App Store Connect → **App Review Information**, fill in:

**Demo Account:**
```
Username: appreview@rosemount.social
Password: ReviewPass2024!
```

**Notes for App Review (copy this text exactly):**
```
Rosemount is a federated social app built on the ActivityPub protocol.

DEMO MODE (no live server required):
1. Launch the app
2. Tap "Sign in with Mastodon"
3. In the "Your Instance" field, type exactly: rosemount-review
4. Tap "Continue"

Demo Mode activates immediately — no network connection required. All tabs
(Home, Communities, Events, Photos, Explore, Notifications, Profile) are
fully navigable with sample content.

VOICE ROOMS: Requires a live WebRTC server. In Demo Mode, tapping "Join"
on a Voice Room shows a "Signaling server unavailable" alert — this is
expected behaviour and not a bug.

DIRECT MESSAGES: End-to-end encrypted. In Demo Mode, sending a message
will fail gracefully with an authentication error — this is expected.

A second demo account is available for testing DM and location features:
Username: appreview2@rosemount.social
Password: ReviewPass2024!

Contact: support@rosemount.social
```

---

## Step 8: Submit for Review

1. In App Store Connect, verify all sections show a green checkmark
2. Click **Submit for Review** (top right of the version page)
3. **Export Compliance** — answer the questionnaire:
   - Does the app use encryption beyond what is in iOS? **No**
   - (Rosemount uses only CryptoKit algorithms covered by EAR 740.17(b))
4. **Advertising Identifier (IDFA)** — select **No** (Rosemount does not use IDFA)
5. **Content Rights** — confirm you have rights to all content in the app
6. Click **Submit**

App Review typically takes 24–48 hours for a first submission. Expedited review
(for critical bug fixes) can be requested at developer.apple.com/contact/app-store/expedite.

---

## Step 9: After Approval

When App Store Connect shows **Approved**:

1. **Release the build:**
   - **Manual release:** Click **Release This Version** in App Store Connect
   - **Phased release:** The Deliverfile sets `phased_release: true` — the build
     rolls out to 1% of users on day 1, increasing automatically over 7 days

2. **Tag the release:**
   ```bash
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. **Monitor after launch:**
   - **Crash rate:** Xcode Organizer → Crashes, or App Store Connect → Metrics
   - **MetricKit:** `Core/Analytics/MetricKitReporter.swift` reports to
     `https://api.rosemount.social/api/v1/telemetry/metrickit`
   - **Reviews:** App Store Connect → Ratings and Reviews (respond within 24h)
   - **Phased rollout:** Monitor for elevated crash rates; pause phased rollout
     via App Store Connect → **Pause Phased Release** if needed

4. **If you need to halt the release:**
   - App Store Connect → version → **Pause Phased Release** (pauses for up to 30 days)
   - Or remove the version entirely if a critical issue is found

---

## Rejection Recovery

The table below covers the most common App Review rejections for social /
ActivityPub apps and how to resolve each.

| Rejection Reason | Guideline | Resolution |
|---|---|---|
| **Demo account required** | 2.1 | Add a working demo account in the App Review Notes field (see Step 7). Ensure `appreview@rosemount.social` is a valid account on `demo.rosemount.social` with content pre-populated. |
| **Privacy Policy URL returns error** | 5.1.1 | Verify `https://rosemount.social/privacy` returns HTTP 200. Check DNS, server uptime, and TLS certificate. Update `AppStoreConfig.privacyPolicyURL` if the URL changes. |
| **Crash on launch** | 2.1 | Attach the crash log from App Store Connect → TestFlight → Crashes or Xcode Organizer. Common cause: `fatalError` in `RosemountApp.swift` ModelContainer init — check SwiftData schema migration. Run `bundle exec fastlane test` and reproduce on a real device before re-submitting. |
| **Missing usage description strings** | 5.1.1 | Ensure all six `NS*UsageDescription` keys are present in `App/Info.plist` and contain user-facing English explanations (not developer notes). See Section 2 of `SUBMISSION_GUIDE.md` for the required keys. |
| **Age rating mismatch** | 1.3 | Re-run the age rating questionnaire in App Store Connect. Rosemount has User Generated Content (social posts, DMs) which requires **12+**. If the questionnaire was answered incorrectly, submit a correction — this does not require a new binary upload. |
