#!/bin/bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="MarketBar"
BUNDLE_ID="local.neo.MarketBar"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
BINARY="$CONTENTS/MacOS/$APP_NAME"

case "$MODE" in
  run|--build-only|--verify|--debug|--logs|--telemetry) ;;
  *) printf '用法：%s [--build-only|--verify|--debug|--logs|--telemetry]\n' "$0" >&2; exit 2 ;;
esac

cd "$ROOT_DIR"
# Keep compiler caches inside the project on restricted development hosts.
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/ModuleCache"
/usr/bin/swift build --disable-sandbox
BUILD_BINARY="$(/usr/bin/swift build --disable-sandbox --show-bin-path)/$APP_NAME"

/usr/bin/pkill -x "$APP_NAME" >/dev/null 2>&1 || true
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
ICON_TEMP="$(mktemp -d "$ROOT_DIR/.build/appicon.XXXXXX")"
trap 'rm -rf "$ICON_TEMP"' EXIT
ICONSET="$ICON_TEMP/AppIcon.iconset"
mkdir "$ICONSET"
for size in 16 32 128 256 512; do
  for scale in 1 2; do
    pixels=$((size * scale))
    suffix=""
    if [[ "$scale" == 2 ]]; then suffix="@2x"; fi
    /usr/bin/sips -z "$pixels" "$pixels" "$ROOT_DIR/Resources/AppIcon.png" \
      --out "$ICONSET/icon_${size}x${size}${suffix}.png" >/dev/null
  done
done
/usr/bin/swift -module-cache-path "$ROOT_DIR/.build/ModuleCache" "$ROOT_DIR/script/make_icon.swift" \
  "$ICONSET" "$CONTENTS/Resources/AppIcon.icns"
cp "$BUILD_BINARY" "$BINARY"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleName</key><string>行情栏</string>
  <key>CFBundleDisplayName</key><string>行情栏</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon.icns</string>
  <key>CFBundleShortVersionString</key><string>1.6.0</string>
  <key>CFBundleVersion</key><string>8</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
/usr/bin/codesign --force --sign - "$APP_BUNDLE"
/usr/bin/codesign --verify --strict "$APP_BUNDLE"
printf '已编译：%s\n' "$APP_BUNDLE"

case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 2
    /usr/bin/pgrep -x "$APP_NAME"
    ;;
  --debug) /usr/bin/lldb -- "$BINARY" ;;
  --logs|--telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "MarketBar"'
    ;;
esac
