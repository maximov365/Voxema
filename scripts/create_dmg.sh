#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# create_dmg.sh — Build Voxema.app and package it as a DMG for local testing
#
# Usage:
#   ./scripts/create_dmg.sh [version]
#   version defaults to "0.0.1-dev" if not provided
#
# Output: dist/Voxema-<version>.dmg
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

VERSION="${1:-0.0.1-dev}"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build_dmg"
STAGING="$BUILD_DIR/staging"
DMG_OUT="$PROJECT_ROOT/dist"
DMG_PATH="$DMG_OUT/Voxema-${VERSION}.dmg"

echo "▶ Building Voxema ${VERSION}…"
mkdir -p "$BUILD_DIR" "$DMG_OUT" "$STAGING"

# ── Archive ──────────────────────────────────────────────────────────────────
xcodebuild archive \
  -scheme Voxema \
  -project "$PROJECT_ROOT/Voxema.xcodeproj" \
  -archivePath "$BUILD_DIR/Voxema.xcarchive" \
  -configuration Release \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGN_STYLE=Manual \
  SKIP_INSTALL=NO \
  2>&1 | tail -20

# ── Export ───────────────────────────────────────────────────────────────────
EXPORT_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>mac-application</string>
  <key>signingStyle</key>
  <string>manual</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$BUILD_DIR/Voxema.xcarchive" \
  -exportPath "$BUILD_DIR/export" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  2>&1 | tail -10

APP_PATH="$BUILD_DIR/export/Voxema.app"

# ── Create DMG ────────────────────────────────────────────────────────────────
echo "▶ Creating DMG…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Voxema $VERSION" \
  -srcfolder "$STAGING" \
  -ov -format UDBZ \
  "$DMG_PATH"

echo ""
echo "✅  DMG created: $DMG_PATH"
echo ""
echo "ℹ️  This is an ad-hoc signed build."
echo "   Users must right-click → Open the first time to bypass Gatekeeper."
echo "   For a notarized release, set up DEVELOPER_ID secrets (see docs/RELEASING.md)."
