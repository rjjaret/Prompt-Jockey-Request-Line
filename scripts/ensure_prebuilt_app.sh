#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PREBUILT_DIR="$ROOT_DIR/prebuilt"
APP_PATH="$PREBUILT_DIR/Prompt Jockey Request Line.app"
ZIP_PATH="$PREBUILT_DIR/Prompt Jockey Request Line.app.zip"

if [[ -d "$APP_PATH" ]]; then
  echo "Prebuilt app already present: $APP_PATH"
  exit 0
fi

if [[ ! -f "$ZIP_PATH" ]]; then
  echo "Missing prebuilt archive: $ZIP_PATH" >&2
  exit 1
fi

echo "Extracting prebuilt app from archive..."
mkdir -p "$PREBUILT_DIR"
ditto -x -k "$ZIP_PATH" "$PREBUILT_DIR"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Extraction finished, but app bundle was not found at: $APP_PATH" >&2
  exit 1
fi

echo "Prebuilt app ready: $APP_PATH"
