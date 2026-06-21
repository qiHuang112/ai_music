#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OHOS_FLUTTER_BIN="${OHOS_FLUTTER_BIN:-${FLUTTER_BIN:-$(command -v flutter || true)}}"
TOOL_HOME="${TOOL_HOME:-/Applications/DevEco-Studio.app/Contents}"

if [[ -z "$OHOS_FLUTTER_BIN" || ! -x "$OHOS_FLUTTER_BIN" ]]; then
  echo "OpenHarmony Flutter SDK was not found." >&2
  echo "Set OHOS_FLUTTER_BIN to the Flutter executable from flutter_flutter." >&2
  exit 127
fi

if [[ -d "$TOOL_HOME" ]]; then
  export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$TOOL_HOME/sdk}"
  export PATH="$TOOL_HOME/tools/ohpm/bin:$TOOL_HOME/tools/hvigor/bin:$TOOL_HOME/tools/node/bin:$PATH"
  export PATH="$TOOL_HOME/sdk/default/openharmony/toolchains:$PATH"
  if [[ -z "${JAVA_HOME:-}" ]]; then
    if [[ -d "$TOOL_HOME/jbr/Contents/Home" ]]; then
      export JAVA_HOME="$TOOL_HOME/jbr/Contents/Home"
    elif [[ -d "$TOOL_HOME/jbr" ]]; then
      export JAVA_HOME="$TOOL_HOME/jbr"
    fi
  fi
fi

export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"

if ! "$OHOS_FLUTTER_BIN" create --help 2>/dev/null | grep -q 'ohos'; then
  echo "The Flutter SDK at $OHOS_FLUTTER_BIN does not support --platforms ohos." >&2
  echo "Use the OpenHarmony Flutter SDK, then rerun with OHOS_FLUTTER_BIN=/path/to/flutter_flutter/bin/flutter." >&2
  exit 64
fi

cd "$ROOT_DIR"

if [[ ! -d ohos ]]; then
  "$OHOS_FLUTTER_BIN" create --platforms ohos --org com.qi --project-name ai_music .
fi

# Entry/plugin ohpm lockfiles contain machine-local Flutter SDK/pub-cache paths.
# Keep only the registry-level ohos/oh-package-lock.json5 in Git and regenerate
# path-based locks during each local build.
rm -f \
  "$ROOT_DIR/ohos/entry/oh-package-lock.json5" \
  "$ROOT_DIR/third_party/just_audio_harmonyos/ohos/oh-package-lock.json5"

"$OHOS_FLUTTER_BIN" pub get

cat > "$ROOT_DIR/ohos/.ohpmrc" <<'EOF'
registry=https://repo.harmonyos.com/ohpm/
strict_ssl=true
EOF

module_json="ohos/entry/src/main/module.json5"
if [[ -f "$module_json" ]] && ! grep -q 'ohos.permission.INTERNET' "$module_json"; then
  echo "Warning: $module_json does not declare ohos.permission.INTERNET." >&2
  echo "Network search and streaming need that permission on HarmonyOS." >&2
fi

build_args=(
  --release
  --dart-define=AI_MUSIC_DISABLE_AUDIO_SERVICE=true
)

if [[ "${OHOS_CODESIGN:-false}" != "true" && " $* " != *" --no-codesign "* ]]; then
  build_args+=(--no-codesign)
fi

"$OHOS_FLUTTER_BIN" build hap "${build_args[@]}" "$@"

echo "HAP output directory: $ROOT_DIR/build/ohos/hap"
