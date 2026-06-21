# AI Music iOS Host

Chinese version: [README.zh-CN.md](README.zh-CN.md)

This directory is the iOS host for the Flutter AI Music app. It should stay focused on Apple platform concerns: launching Flutter, registering plugins, declaring iOS capabilities, signing, packaging, and device installation.

Shared product behavior belongs in Dart under `lib/src/`. Search providers, playback rules, downloads, cache repair, playlists, settings state, and UI state should not be reimplemented in Swift.

## Responsibilities

- `Runner/AppDelegate.swift` boots the Flutter host and registers generated plugins with the implicit Flutter engine.
- `Runner/SceneDelegate.swift` is the UIKit scene entry point used by the Flutter scene delegate.
- `Runner/Info.plist` declares iOS runtime capabilities such as background audio, local network usage, and App Transport Security exceptions used by the music sources.
- `Runner.xcodeproj` and `Runner.xcworkspace` hold signing, build phases, Swift Package/CocoaPods integration, and archive settings.
- `../tool/build_ios_ipa.sh` is the supported command-line IPA export path.

## What Not To Put Here

- Music search, resolver fallback behavior, provider-specific retry rules, or ranking.
- Playback queue behavior, download state, cache metadata, or playlist logic.
- Flutter screen state, localization strings, or widget behavior.

Those are shared Flutter concerns and should be changed in `lib/src/` by the cross-platform app owners.

## Current iOS Capabilities

- Bundle ID: `com.qi.ai.music`.
- Minimum deployment target: iOS 13.
- Background audio: `UIBackgroundModes` includes `audio`.
- Local network prompt: `NSLocalNetworkUsageDescription` explains music-source access.
- ATS: `NSAllowsArbitraryLoads` and `NSAllowsLocalNetworking` are currently enabled for development, local sources, and plain-HTTP music endpoint compatibility. This is not the long-term security target for external distribution; before TestFlight/App Store, narrow it to `NSAllowsLocalNetworking` plus required domain exceptions.
- Distribution today is development signing with a Personal Team. App Store, TestFlight, and ad-hoc distribution require the appropriate Apple Developer account setup.

## Build And Install

Always use the Flutter SDK checked out beside the app:

```bash
cd /Users/huangqi/AIHome/ai_music
/Users/huangqi/AIHome/tools/flutter/bin/flutter pub get
```

Build a development IPA for registered devices. This is the default export method:

```bash
./tool/build_ios_ipa.sh
```

The output is written to:

```text
build/ios/ipa/
```

For a real device, first make sure:

- iPhone Developer Mode is enabled.
- The device trusts the Apple Development profile in Settings.
- Xcode has selected the correct Team for `Runner`.
- `ios/Flutter/Generated.xcconfig` points to `/Users/huangqi/AIHome/tools/flutter`, not `tools/flutter_ohos`.

## Friend Install Builds

`AI Music.ipa` is signed for the current development account and registered devices. Do not treat it as a universal install package.

For friends without access to this signing profile, use a resignable IPA and have them install it through AltStore, SideStore, or Sideloadly with their own Apple ID. iOS cannot install a random IPA by tapping it in Files.

If CocoaPods integration changes are committed later, include the project/workspace changes and `ios/Podfile.lock` together. Keep `Pods/` ignored.

## Troubleshooting

- `In iOS 14+ debug mode...`: a debug build was installed. Install a release/profile build or an exported IPA instead.
- `profile has not been explicitly trusted`: open iPhone Settings, then trust the developer profile under General > VPN & Device Management.
- `Developer Mode required`: enable Developer Mode under Privacy & Security and restart the device.
- `FLUTTER_ROOT` points to `tools/flutter_ohos`: run `/Users/huangqi/AIHome/tools/flutter/bin/flutter clean` and then `pub get` from this app.
- BuguYY works on Android but fails on simulator/Mac: check local VPN/proxy and DNS first. The simulator shares the Mac network path.
- `errSecInternalComponent` during codesign: allow the Apple Development private key for `codesign` in Keychain, or refresh the key partition list.

## Verification

```bash
/Users/huangqi/AIHome/tools/flutter/bin/flutter analyze
/Users/huangqi/AIHome/tools/flutter/bin/flutter test
/Users/huangqi/AIHome/tools/flutter/bin/flutter build ios --release
```
