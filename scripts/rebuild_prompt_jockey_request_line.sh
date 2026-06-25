#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MRT_DIR="$ROOT_DIR/magenta-realtime-pjrl"
BUILD_DIR="$MRT_DIR/build-pjrl"
PREBUILT_DIR="$ROOT_DIR/prebuilt"
OUT_APP="$PREBUILT_DIR/Prompt Jockey Request Line.app"
OUT_ZIP="$PREBUILT_DIR/Prompt Jockey Request Line.app.zip"

FORCE_RECONFIGURE=0
if [[ "${1:-}" == "--reconfigure" ]]; then
  FORCE_RECONFIGURE=1
fi

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

configure_build() {
  echo "Configuring build in $BUILD_DIR"
  "$CMAKE_BIN" -S "$MRT_DIR" -B "$BUILD_DIR" \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
}

extract_working_directory_from_gitupdate() {
  local update_script="$1"
  grep -m1 -E 'WORKING_DIRECTORY "[^"]+"' "$update_script" \
    | sed -E 's/.*WORKING_DIRECTORY "([^"]+)".*/\1/'
}

clean_fetchcontent_dependency_state() {
  local dep_name="$1"
  local update_script="$2"
  local dep_checkout_dir
  dep_checkout_dir="$(extract_working_directory_from_gitupdate "$update_script" || true)"

  local dep_src="$BUILD_DIR/_deps/${dep_name}-src"
  local dep_subbuild="$BUILD_DIR/_deps/${dep_name}-subbuild"
  local dep_stamp_dir="$BUILD_DIR/src/${dep_name}-populate-stamp"

  echo "Detected corrupted FetchContent git state for dependency '$dep_name'."
  echo "Cleaning dependency state so CMake can perform a fresh clone..."

  if [[ -n "$dep_checkout_dir" && "$dep_checkout_dir" == "$BUILD_DIR"/* ]]; then
    rm -rf "$dep_checkout_dir"
  fi

  rm -rf "$dep_src" "$dep_subbuild" "$dep_stamp_dir"

  local tmp_pattern
  for tmp_pattern in "$BUILD_DIR/tmp/${dep_name}-populate-"*; do
    if [[ -e "$tmp_pattern" ]]; then
      rm -rf "$tmp_pattern"
    fi
  done
}

configure_with_fetchcontent_repair() {
  local max_attempts=10
  local attempt=1

  while true; do
    local cfg_log
    cfg_log="$(mktemp)"

    set +e
    configure_build 2>&1 | tee "$cfg_log"
    local rc=${PIPESTATUS[0]}
    set -e

    if [[ $rc -eq 0 ]]; then
      rm -f "$cfg_log"
      return 0
    fi

    if ! grep -q "not a git repository: '.git'" "$cfg_log"; then
      echo "Configure failed for a non-FetchContent-git reason. See output above." >&2
      rm -f "$cfg_log"
      return $rc
    fi

    local update_script dep_name
    update_script="$(grep -oE '/[^ ]+-populate-gitupdate\.cmake' "$cfg_log" | head -n1 || true)"
    rm -f "$cfg_log"

    if [[ -z "$update_script" ]]; then
      echo "FetchContent git failure detected but could not determine dependency name." >&2
      return 1
    fi

    dep_name="$(basename "$update_script")"
    dep_name="${dep_name%-populate-gitupdate.cmake}"
    clean_fetchcontent_dependency_state "$dep_name" "$update_script"

    if [[ $attempt -ge $max_attempts ]]; then
      echo "Exceeded $max_attempts configure-repair attempts." >&2
      return 1
    fi
    attempt=$((attempt + 1))
  done
}

if [[ $FORCE_RECONFIGURE -eq 1 || ! -f "$BUILD_DIR/CMakeCache.txt" ]]; then
  configure_with_fetchcontent_repair
else
  echo "Skipping configure (existing cache found). Use --reconfigure to force."
fi

echo "Building local collider app target"
"$CMAKE_BIN" --build "$BUILD_DIR" --target mrt2_collider -j"$(sysctl -n hw.ncpu)"

APP_CANDIDATE="$BUILD_DIR/examples/collider/mrt2_collider.app"
if [[ ! -d "$APP_CANDIDATE" ]]; then
  echo "Expected app bundle not found at $APP_CANDIDATE" >&2
  exit 1
fi

mkdir -p "$PREBUILT_DIR"
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

rm -f "$OUT_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$OUT_APP" "$OUT_ZIP"

if git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT_DIR" add -A -- "$OUT_ZIP"
fi

echo "Built app: $OUT_APP"
echo "Packaged app archive: $OUT_ZIP"
echo "Launch with: ./scripts/ensure_prebuilt_app.sh && open \"$OUT_APP\""
