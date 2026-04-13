# App Store Screenshots

This directory holds the screenshots uploaded to App Store Connect by `fastlane deliver`.

## How to Capture

Run the following on a Mac with Xcode and a compatible simulator:

```bash
bundle exec fastlane screenshots
```

This executes the `RosemountUITests` scheme (which calls `snapshot()` at key screens),
saves `.png` files into `fastlane/screenshots/en-US/`, and generates an HTML preview
via `frame_screenshots`.

## Required Device Sizes

| Device | Resolution | App Store Label |
|---|---|---|
| iPhone 15 Pro Max | 1290 × 2796 px | 6.7" Super Retina XDR |
| iPhone 15 | 1179 × 2556 px | 6.1" Super Retina XDR |
| iPad Pro (12.9-inch) | 2048 × 2732 px | 12.9" iPad Pro |

The App Store requires **at minimum** 3 screenshots for the 6.7" iPhone size.
iPad screenshots are required only if you enable iPad in your App Store listing.

## Device Configuration

Devices are defined in `../Snapfile`. To add or remove a device, edit that file.

## Screenshot Screens (recommended order)

1. **Home Timeline** — shows the federated social feed
2. **Community Feed** — a community with posts and members
3. **Compose / New Post** — the rich text editor with media
4. **Direct Messages** — encrypted conversation thread
5. **Profile** — user profile with stats and post grid

## Notes

- Screenshots must not contain device frames (Xcode simulator adds none by default)
- `frame_screenshots` wraps screenshots in a device frame using frameit — requires
  frames to be downloaded: `bundle exec fastlane frameit download_frames`
- To skip framing and upload raw screenshots: set `skip_frame_screenshots true` in
  the `screenshots` lane or pass `--skip_frame_screenshots` on the command line
- All screenshots in this directory are gitignored by default — add them to source
  control only if you want to pin a specific set for CI

## Troubleshooting

| Problem | Fix |
|---|---|
| "No simulators found" | Run `xcrun simctl list devices` and verify the device names match `Snapfile` |
| Screenshots are blank | Ensure `snapshot()` calls exist in `RosemountUITests` at the right points |
| Wrong resolution | Check device name in `Snapfile` matches the exact Xcode simulator name |
