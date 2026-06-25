#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MRT_DIR="$ROOT_DIR/magenta-realtime-pjrl"
BUILD_DIR="$MRT_DIR/build-pjrl"
OUT_DIR="$ROOT_DIR/runtime"
OUT_APP="$OUT_DIR/Prompt Jockey Request Line.app"

if [[ ! -d "$MRT_DIR" ]]; then
  echo "Missing source directory: $MRT_DIR" >&2
  exit 1
fi

if command -v cmake >/dev/null 2>&1; then
  CMAKE_BIN="$(command -v cmake)"
elif [[ -x "$ROOT_DIR/.venv/bin/cmake" ]]; then
  CMAKE_BIN="$ROOT_DIR/.venv/bin/cmake"
else
  echo "cmake is required but not found in PATH or $ROOT_DIR/.venv/bin/cmake" >&2
  exit 1
fi

if ! command -v npm >/dev/null 2>&1; then
  echo "npm is required but not found in PATH" >&2
  exit 1
fi

echo "Configuring build in $BUILD_DIR"
"$CMAKE_BIN" -S "$MRT_DIR" -B "$BUILD_DIR" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5

echo "Building local collider app target"
"$CMAKE_BIN" --build "$BUILD_DIR" --target mrt2_collider -j"$(sysctl -n hw.ncpu)"

APP_CANDIDATE="$BUILD_DIR/examples/collider/mrt2_collider.app"
if [[ ! -d "$APP_CANDIDATE" ]]; then
  echo "Expected app bundle not found at $APP_CANDIDATE" >&2
  exit 1
fi

mkdir -p "$OUT_DIR"
rm -rf "$OUT_APP"
cp -R "$APP_CANDIDATE" "$OUT_APP"

# Match deploy behavior: embed built Collider UI into app resources.
UI_DIST="$MRT_DIR/examples/collider/ui/dist"
if [[ -d "$UI_DIST" ]]; then
  mkdir -p "$OUT_APP/Contents/Resources/collider_ui"
  cp -R "$UI_DIST"/. "$OUT_APP/Contents/Resources/collider_ui/"
else
  echo "Warning: UI dist not found at $UI_DIST"
fi

# Match deploy behavior: place mlx.metallib next to binary when available.
METALLIB="$BUILD_DIR/_deps/mlx-build/mlx/backend/metal/kernels/mlx.metallib"
if [[ -f "$METALLIB" ]]; then
  cp "$METALLIB" "$OUT_APP/Contents/MacOS/mlx.metallib"
else
  echo "Warning: mlx.metallib not found at $METALLIB"
fi

PLIST="$OUT_APP/Contents/Info.plist"
if [[ ! -f "$PLIST" ]]; then
  echo "Info.plist missing in built app" >&2
  exit 1
fi

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.google.promptjockeyrequestline' "$PLIST"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName MRT2 - Collider - Prompt Jockey Request Line' "$PLIST"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PLIST" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName MRT2 - Collider - Prompt Jockey Request Line' "$PLIST"
else
  /usr/libexec/PlistBuddy -c 'Add :CFBundleDisplayName string MRT2 - Collider - Prompt Jockey Request Line' "$PLIST"
fi

UI_HTML="$OUT_APP/Contents/Resources/collider_ui/index.html"
if [[ -f "$UI_HTML" ]]; then
  perl -0777 -pe 's#<title>.*?</title>#<title>MRT2 - Collider - Prompt Jockey Request Line</title>#s' "$UI_HTML" > "$UI_HTML.tmp"
  mv "$UI_HTML.tmp" "$UI_HTML"
fi

ENT="$MRT_DIR/examples/collider/ColliderEntitlements.plist"
if [[ -f "$ENT" ]]; then
  echo "Codesigning app bundle (ad-hoc)"
  codesign --force --deep --sign - --entitlements "$ENT" "$OUT_APP"
else
  echo "Skipping codesign: missing entitlements file at $ENT"
fi

echo "Built app: $OUT_APP"
echo "Launch with: open \"$OUT_APP\""
