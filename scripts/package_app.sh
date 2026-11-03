#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/学习休息倒计时.app"
RELEASE_DIR="$ROOT_DIR/build/release"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_DIR/Contents/Info.plist")
PACKAGE_NAME="FocusBreakTimer-${VERSION}-macOS-universal"

codesign --verify --deep --strict "$APP_DIR"
lipo "$APP_DIR/Contents/MacOS/FocusBreakTimer" -verify_arch arm64 x86_64

mkdir -p "$RELEASE_DIR"
STAGING_DIR=$(mktemp -d "$ROOT_DIR/build/package.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT

ditto "$APP_DIR" "$STAGING_DIR/学习休息倒计时.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "学习休息倒计时 $VERSION" \
  -srcfolder "$STAGING_DIR" \
  -format UDZO -ov "$RELEASE_DIR/$PACKAGE_NAME.dmg"

ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$RELEASE_DIR/$PACKAGE_NAME.zip"
(
  cd "$RELEASE_DIR"
  shasum -a 256 "$PACKAGE_NAME.dmg" "$PACKAGE_NAME.zip" > SHA256SUMS.txt
)

echo "$RELEASE_DIR"
