# AI Music

Flutter music search, cache, and playback app.

The active baseline is the Flutter version with LAN library synchronization on
`main`. See [current project state](CURRENT_STATE.md) and the
[LAN server guide](tool/LAN_MUSIC_SERVER_README.txt).

## Local SDK

From this project's root, use the existing local Flutter SDK (or set
`FLUTTER` to your own SDK executable):

```bash
export FLUTTER=/Users/huangqi/AIHome/tools/flutter/bin/flutter
"$FLUTTER" pub get
```

## Project checks

The current test flow stays the same:

```bash
"$FLUTTER" test --no-pub
"$FLUTTER" analyze --no-pub
```

## iOS IPA build

The iOS target uses bundle id `com.qi.ai.music` and supports background audio plus HTTP music streams. The iOS host is documented in [English](ios/README.md) and [Chinese](ios/README.zh-CN.md); shared app behavior remains in Dart under `lib/src/`.

Before the first signed IPA build, open the workspace once and select your Apple signing team:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
open ios/Runner.xcworkspace
```

In Xcode, select `Runner` > `Signing & Capabilities`, choose a Team, and keep the bundle id as `com.qi.ai.music`.

Build a development IPA for the current Personal Team or registered development devices:

```bash
tool/build_ios_ipa.sh
```

That is equivalent to `IOS_EXPORT_METHOD=development tool/build_ios_ipa.sh`.

The script writes the IPA to:

```text
build/ios/ipa/
```

Useful variants:

```bash
# Explicit development-signed IPA for registered development devices.
IOS_EXPORT_METHOD=development tool/build_ios_ipa.sh

# Ad hoc IPA for a paid Apple Developer account with registered devices.
IOS_EXPORT_METHOD=ad-hoc \
IOS_TEAM_ID=YOURTEAMID \
IOS_PROVISIONING_PROFILE="AI Music Ad Hoc" \
tool/build_ios_ipa.sh

# Use a fully custom export options plist.
IOS_EXPORT_OPTIONS_PLIST=ios/ExportOptions.plist tool/build_ios_ipa.sh
```

Install the resulting IPA with Apple Configurator, Finder device management, MDM, or any other trusted IPA installation route supported by the signing method you used.

For local development with a Personal Team, keep the default `development` export method. That IPA is only for registered devices trusted by the signing profile; it is not a universal package. For friends who need to install without your signing profile, provide a resignable IPA and have them use AltStore, SideStore, or Sideloadly with their own Apple ID.
