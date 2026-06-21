# AI Music

Flutter music search, cache, and playback app.

## Local SDK

Use the Flutter SDK checked out beside this app:

```bash
../tools/flutter/bin/flutter pub get
```

## Project checks

The current test flow stays the same:

```bash
../tools/flutter/bin/flutter test
../tools/flutter/bin/flutter analyze
```

## iOS IPA build

The iOS target uses bundle id `com.qi.ai.music` and supports background audio plus HTTP music streams.

Before the first signed IPA build, open the workspace once and select your Apple signing team:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
open ios/Runner.xcworkspace
```

In Xcode, select `Runner` > `Signing & Capabilities`, choose a Team, and keep the bundle id as `com.qi.ai.music`.

Build an installable IPA without using the App Store:

```bash
IOS_EXPORT_METHOD=ad-hoc tool/build_ios_ipa.sh
```

The script writes the IPA to:

```text
build/ios/ipa/
```

Useful variants:

```bash
# Development-signed IPA for registered development devices.
IOS_EXPORT_METHOD=development tool/build_ios_ipa.sh

# Manual provisioning profile by name or UUID.
IOS_EXPORT_METHOD=ad-hoc \
IOS_TEAM_ID=YOURTEAMID \
IOS_PROVISIONING_PROFILE="AI Music Ad Hoc" \
tool/build_ios_ipa.sh

# Use a fully custom export options plist.
IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist tool/build_ios_ipa.sh
```

Install the resulting IPA with Apple Configurator, Finder device management, MDM, or any other trusted IPA installation route supported by the signing method you used.
