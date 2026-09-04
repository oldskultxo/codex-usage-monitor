#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT/build/CodexUsageMonitor.app"
ICON_PATH="$ROOT/build/AppIcon.icns"
ICON_SOURCE="$ROOT/macos/assets/icon.png"
ICONSET_PARENT="$(mktemp -d "${TMPDIR:-/tmp}/codex-usage-monitor.XXXXXX")"
ICONSET_DIR="$ICONSET_PARENT/AppIcon.iconset"
ICON_OUTPUT="$ICONSET_PARENT/AppIcon.icns"
mkdir -p "$ICONSET_DIR"
trap 'rm -rf "$ICONSET_PARENT"' EXIT

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon: $ICON_SOURCE" >&2
  exit 1
fi

swift build --package-path "$ROOT/macos" -c release
BIN_DIR="$(swift build --package-path "$ROOT/macos" -c release --show-bin-path)"

for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" "$ICON_SOURCE" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done

mkdir -p "$ROOT/build"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_OUTPUT"
mv "$ICON_OUTPUT" "$ICON_PATH"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/Contents/MacOS" "$BUILD_DIR/Contents/Resources/core"
cp "$BIN_DIR/CodexUsageMonitor" "$BUILD_DIR/Contents/MacOS/CodexUsageMonitor"
cp "$ROOT/macos/Info.plist" "$BUILD_DIR/Contents/Info.plist"
cp "$ROOT/core/monitor.mjs" "$BUILD_DIR/Contents/Resources/core/monitor.mjs"
cp "$ICON_PATH" "$BUILD_DIR/Contents/Resources/AppIcon.icns"

chmod +x "$BUILD_DIR/Contents/MacOS/CodexUsageMonitor"
echo "Built $BUILD_DIR"
