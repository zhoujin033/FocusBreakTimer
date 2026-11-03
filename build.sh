#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$ROOT_DIR/学习休息倒计时.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"

rm -rf "$BUILD_DIR" "$APP_DIR"
mkdir -p "$BUILD_DIR" "$MACOS_DIR" "$RESOURCES_DIR"
mkdir -p "$BUILD_DIR/ModuleCache"
mkdir -p "$BUILD_DIR/tmp"

export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/ModuleCache"
export TMPDIR="$BUILD_DIR/tmp"

ARCH_FLAGS=(-arch "$(uname -m)")
if [[ "${UNIVERSAL_BUILD:-0}" == "1" ]]; then
  ARCH_FLAGS=(-arch arm64 -arch x86_64)
fi

clang \
  "${ARCH_FLAGS[@]}" \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  "$ROOT_DIR/Sources/main.m" \
  "$ROOT_DIR/Sources/BreakTimerPolicy.m" \
  "$ROOT_DIR/Sources/DisplayPowerController.m" \
  "$ROOT_DIR/Sources/EmergencySkipQuotaStore.m" \
  "$ROOT_DIR/Sources/MeetingScheduleStore.m" \
  "$ROOT_DIR/Sources/RestObligationStore.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  "$ROOT_DIR/Sources/StudyStatisticsCalculator.m" \
  "$ROOT_DIR/Sources/StudyStatisticsWindowController.m" \
  -o "$MACOS_DIR/FocusBreakTimer" \
  -framework Cocoa -framework IOKit

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  "$ROOT_DIR/Tools/IconGenerator.m" \
  -o "$BUILD_DIR/IconGenerator" \
  -framework Cocoa

"$BUILD_DIR/IconGenerator" "$ICONSET_DIR" "$ROOT_DIR/AppIconPreview.png" "$RESOURCES_DIR/AppIcon.icns"

cp "$ROOT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

chmod +x "$MACOS_DIR/FocusBreakTimer"
codesign --force --deep --sign - "$APP_DIR" >/dev/null

echo "$APP_DIR"
