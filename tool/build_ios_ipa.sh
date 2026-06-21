#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/../tools/flutter/bin/flutter}"

# iOS signing is selected at export time so the Flutter/Dart app code can stay
# shared across Android and iOS. This project defaults to development because
# the current local install flow uses a Personal Team.
# Common values:
#   development: Personal Team or local devices registered to a development team.
#   ad-hoc:      registered devices on a paid Apple Developer account.
#   app-store:   App Store or TestFlight submission.
#   enterprise:  enterprise distribution where that account type is available.
EXPORT_METHOD="${IOS_EXPORT_METHOD:-development}"
EXPORT_OPTIONS_PLIST="${IOS_EXPORT_OPTIONS_PLIST:-}"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.qi.ai.music}"

# IOS_TEAM_ID pins automatic signing to one Apple team. Leave it empty when
# Xcode's Runner target already has the intended Team selected.
TEAM_ID="${IOS_TEAM_ID:-}"

# IOS_PROVISIONING_PROFILE switches export to manual signing and should be the
# profile name or UUID for IOS_BUNDLE_ID.
PROVISIONING_PROFILE="${IOS_PROVISIONING_PROFILE:-}"

case "$EXPORT_METHOD" in
  app-store | ad-hoc | development | enterprise) ;;
  *)
    echo "Unsupported IOS_EXPORT_METHOD: $EXPORT_METHOD" >&2
    echo "Use one of: app-store, ad-hoc, development, enterprise." >&2
    exit 64
    ;;
esac

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter SDK not found at $FLUTTER_BIN" >&2
  echo "Set FLUTTER_BIN to the Flutter executable if needed." >&2
  exit 127
fi

if ! xcodebuild -version >/dev/null 2>&1; then
  echo "A full Xcode installation is required to build an iOS IPA." >&2
  echo "Install Xcode, then run:" >&2
  echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer" >&2
  echo "  sudo xcodebuild -runFirstLaunch" >&2
  exit 69
fi

xml_escape() {
  local value="$1"
  value="${value//&/&amp;}"
  value="${value//</&lt;}"
  value="${value//>/&gt;}"
  value="${value//\"/&quot;}"
  value="${value//\'/&apos;}"
  printf '%s' "$value"
}

write_string_key() {
  local key="$1"
  local value="$2"
  printf '\t<key>%s</key>\n' "$(xml_escape "$key")"
  printf '\t<string>%s</string>\n' "$(xml_escape "$value")"
}

write_export_options() {
  local output="$1"
  local signing_style="automatic"
  if [[ -n "$PROVISIONING_PROFILE" ]]; then
    signing_style="manual"
  fi

  {
    printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
    printf '%s\n' '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
    printf '%s\n' '<plist version="1.0">'
    printf '%s\n' '<dict>'
    write_string_key method "$EXPORT_METHOD"
    write_string_key signingStyle "$signing_style"
    printf '\t<key>stripSwiftSymbols</key>\n\t<true/>\n'
    printf '\t<key>compileBitcode</key>\n\t<false/>\n'
    if [[ -n "$TEAM_ID" ]]; then
      write_string_key teamID "$TEAM_ID"
    fi
    if [[ -n "$PROVISIONING_PROFILE" ]]; then
      printf '\t<key>provisioningProfiles</key>\n\t<dict>\n'
      printf '\t\t<key>%s</key>\n' "$(xml_escape "$BUNDLE_ID")"
      printf '\t\t<string>%s</string>\n' "$(xml_escape "$PROVISIONING_PROFILE")"
      printf '\t</dict>\n'
    fi
    printf '%s\n' '</dict>'
    printf '%s\n' '</plist>'
  } > "$output"
}

cd "$ROOT_DIR"

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

"$FLUTTER_BIN" pub get

build_args=(--release)
if [[ -n "$EXPORT_OPTIONS_PLIST" ]]; then
  build_args+=(--export-options-plist="$EXPORT_OPTIONS_PLIST")
else
  generated_plist="$ROOT_DIR/build/ios/ExportOptions.$EXPORT_METHOD.plist"
  mkdir -p "$(dirname "$generated_plist")"
  write_export_options "$generated_plist"
  build_args+=(--export-options-plist="$generated_plist")
  echo "Using generated export options: $generated_plist"
fi

"$FLUTTER_BIN" build ipa "${build_args[@]}" "$@"

echo "IPA output directory: $ROOT_DIR/build/ios/ipa"
