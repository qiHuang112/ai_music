#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FLUTTER_BIN="${FLUTTER_BIN:-$ROOT_DIR/../tools/flutter/bin/flutter}"
ANDROID_HOME="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-}"
MAX_APK_SIZE_MB="${MAX_APK_SIZE_MB:-60}"
PACKAGE_NAME="com.qi.ai.music"
ABI="arm64-v8a"
TARGET_PLATFORM="android-arm64"

if [[ ! -x "$FLUTTER_BIN" ]]; then
  echo "Flutter SDK not found at $FLUTTER_BIN" >&2
  echo "Set FLUTTER_BIN to the Flutter executable if needed." >&2
  exit 127
fi

if [[ -z "$ANDROID_HOME" ]]; then
  local_properties="$ROOT_DIR/android/local.properties"
  if [[ -f "$local_properties" ]]; then
    ANDROID_HOME="$(awk -F= '$1 == "sdk.dir" { print $2 }' "$local_properties" | tail -n 1)"
  fi
fi

if [[ -z "$ANDROID_HOME" || ! -d "$ANDROID_HOME" ]]; then
  echo "Android SDK not found. Set ANDROID_HOME, ANDROID_SDK_ROOT, or android/local.properties sdk.dir." >&2
  exit 69
fi

ndk_revision() {
  local ndk_dir="$1"
  local source_properties="$ndk_dir/source.properties"
  if [[ -f "$source_properties" ]]; then
    awk -F= '$1 == "Pkg.Revision" {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
      print $2
      exit
    }' "$source_properties"
  fi
}

ndk_matches_version() {
  local ndk_dir="$1"
  local expected_version="$2"
  [[ -d "$ndk_dir" ]] || return 1
  [[ "$(basename "$ndk_dir")" == "$expected_version" ]] && return 0
  [[ "$(ndk_revision "$ndk_dir")" == "$expected_version" ]]
}

NDK_VERSION="$(awk -F\" '/ndkVersion[[:space:]]*=/{ print $2; exit }' "$ROOT_DIR/android/app/build.gradle.kts")"
if [[ -n "$NDK_VERSION" && "${AI_MUSIC_SKIP_NDK_PREFLIGHT:-}" != "1" ]]; then
  ndk_found=false
  for ndk_candidate in "$ANDROID_HOME/ndk/$NDK_VERSION" "$ANDROID_NDK_HOME"; do
    if [[ -n "$ndk_candidate" ]] && ndk_matches_version "$ndk_candidate" "$NDK_VERSION"; then
      ndk_found=true
      break
    fi
  done
  if [[ "$ndk_found" != true ]]; then
    echo "Android NDK $NDK_VERSION not found." >&2
    echo "Checked $ANDROID_HOME/ndk/$NDK_VERSION and ANDROID_NDK_HOME." >&2
    echo "Install it with sdkmanager \"ndk;$NDK_VERSION\", set ANDROID_NDK_HOME to that NDK, or set AI_MUSIC_SKIP_NDK_PREFLIGHT=1 to let Gradle resolve it." >&2
    exit 69
  fi
fi

find_build_tool() {
  local name="$1"
  find "$ANDROID_HOME/build-tools" -name "$name" -type f 2>/dev/null | sort -V | tail -n 1
}

AAPT="$(find_build_tool aapt)"
APKSIGNER="$(find_build_tool apksigner)"

if [[ -z "$AAPT" || ! -x "$AAPT" ]]; then
  echo "aapt not found under $ANDROID_HOME/build-tools." >&2
  exit 69
fi

if [[ -z "$APKSIGNER" || ! -x "$APKSIGNER" ]]; then
  echo "apksigner not found under $ANDROID_HOME/build-tools." >&2
  exit 69
fi

file_size_bytes() {
  if stat -f%z "$1" >/dev/null 2>&1; then
    stat -f%z "$1"
  else
    stat -c%s "$1"
  fi
}

version_name() {
  awk -F: '$1 == "version" {
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)
    split($2, parts, "+")
    print parts[1]
  }' "$ROOT_DIR/pubspec.yaml" | head -n 1
}

cd "$ROOT_DIR"

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

rm -f \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk" \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-release.apk.sha1" \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-$ABI-release.apk" \
  "$ROOT_DIR/build/app/outputs/flutter-apk/app-$ABI-release.apk.sha1" \
  "$ROOT_DIR/build/release/"*android-arm64*.apk \
  "$ROOT_DIR/build/release/"*android-arm64*.apk.sha256

"$FLUTTER_BIN" pub get
"$FLUTTER_BIN" build apk --release --target-platform "$TARGET_PLATFORM" --split-per-abi "$@"

source_apk="$ROOT_DIR/build/app/outputs/flutter-apk/app-$ABI-release.apk"
if [[ ! -f "$source_apk" ]]; then
  echo "Expected APK was not created: $source_apk" >&2
  exit 1
fi

mkdir -p "$ROOT_DIR/build/release"
version="$(version_name)"
if [[ -z "$version" ]]; then
  version="unknown"
fi
output_apk="$ROOT_DIR/build/release/ai-music-v$version-android-arm64.apk"
cp -f "$source_apk" "$output_apk"

"$APKSIGNER" verify --verbose --print-certs "$output_apk" >/dev/null

badging="$("$AAPT" dump badging "$output_apk")"
if ! printf '%s\n' "$badging" | grep -q "^package: name='$PACKAGE_NAME'"; then
  echo "Unexpected package metadata:" >&2
  echo "$badging" | sed -n '1,3p' >&2
  exit 1
fi

zip_entries="$(zipinfo -1 "$output_apk")"

if ! printf '%s\n' "$zip_entries" | grep -q "^lib/$ABI/libflutter.so$"; then
  echo "Missing lib/$ABI/libflutter.so; this is not the expected arm64 APK." >&2
  exit 1
fi

foreign_libs="$(
  printf '%s\n' "$zip_entries" |
    awk -v abi="$ABI" 'index($0, "lib/") == 1 && $0 ~ /\.so$/ {
      split($0, parts, "/")
      if (parts[2] != abi) {
        print
      }
    }'
)"
if [[ -n "$foreign_libs" ]]; then
  echo "APK contains native libraries outside lib/$ABI; do not publish it as android-arm64." >&2
  printf '%s\n' "$foreign_libs" >&2
  exit 1
fi

size_bytes="$(file_size_bytes "$output_apk")"
max_bytes=$((MAX_APK_SIZE_MB * 1024 * 1024))
if (( size_bytes > max_bytes )); then
  printf 'APK is too large: %.2f MB (limit: %s MB)\n' \
    "$(awk "BEGIN { print $size_bytes / 1024 / 1024 }")" \
    "$MAX_APK_SIZE_MB" >&2
  exit 1
fi

shasum -a 256 "$output_apk" | tee "$output_apk.sha256"
printf 'Built %s (%.2f MB)\n' \
  "$output_apk" \
  "$(awk "BEGIN { print $size_bytes / 1024 / 1024 }")"
