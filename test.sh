#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT_DIR/build/tests"

mkdir -p "$BUILD_DIR"

cc -std=c11 -Wall -Wextra -Werror \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/CountdownLayoutTests.c" \
  -lm -o "$BUILD_DIR/CountdownLayoutTests"

"$BUILD_DIR/CountdownLayoutTests"

if [[ "${1:-}" == "--layout-only" ]]; then
  exit 0
fi

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/CountdownViewTests.m" \
  "$ROOT_DIR/Sources/DisplayPowerController.m" \
  "$ROOT_DIR/Sources/BreakTimerPolicy.m" \
  "$ROOT_DIR/Sources/EmergencySkipQuotaStore.m" \
  "$ROOT_DIR/Sources/MeetingScheduleStore.m" \
  "$ROOT_DIR/Sources/RestObligationStore.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  "$ROOT_DIR/Sources/StudyStatisticsCalculator.m" \
  "$ROOT_DIR/Sources/StudyStatisticsWindowController.m" \
  -o "$BUILD_DIR/CountdownViewTests" \
  -framework Cocoa -framework IOKit

"$BUILD_DIR/CountdownViewTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/BreakTimerPolicyTests.m" \
  "$ROOT_DIR/Sources/BreakTimerPolicy.m" \
  -o "$BUILD_DIR/BreakTimerPolicyTests" \
  -framework Foundation \
  -framework CoreGraphics

"$BUILD_DIR/BreakTimerPolicyTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/EmergencySkipQuotaStoreTests.m" \
  "$ROOT_DIR/Sources/EmergencySkipQuotaStore.m" \
  -o "$BUILD_DIR/EmergencySkipQuotaStoreTests" \
  -framework Foundation

"$BUILD_DIR/EmergencySkipQuotaStoreTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/MeetingScheduleStoreTests.m" \
  "$ROOT_DIR/Sources/MeetingScheduleStore.m" \
  -o "$BUILD_DIR/MeetingScheduleStoreTests" \
  -framework Foundation

"$BUILD_DIR/MeetingScheduleStoreTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/RestObligationStoreTests.m" \
  "$ROOT_DIR/Sources/RestObligationStore.m" \
  -o "$BUILD_DIR/RestObligationStoreTests" \
  -framework Foundation

"$BUILD_DIR/RestObligationStoreTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/BreakTimerControllerTests.m" \
  "$ROOT_DIR/Sources/DisplayPowerController.m" \
  "$ROOT_DIR/Sources/BreakTimerPolicy.m" \
  "$ROOT_DIR/Sources/EmergencySkipQuotaStore.m" \
  "$ROOT_DIR/Sources/MeetingScheduleStore.m" \
  "$ROOT_DIR/Sources/RestObligationStore.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  "$ROOT_DIR/Sources/StudyStatisticsCalculator.m" \
  "$ROOT_DIR/Sources/StudyStatisticsWindowController.m" \
  -o "$BUILD_DIR/BreakTimerControllerTests" \
  -framework Cocoa -framework IOKit

"$BUILD_DIR/BreakTimerControllerTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/StudyHistoryStoreTests.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  -o "$BUILD_DIR/StudyHistoryStoreTests" \
  -framework Foundation

"$BUILD_DIR/StudyHistoryStoreTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/StudyStatisticsCalculatorTests.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  "$ROOT_DIR/Sources/StudyStatisticsCalculator.m" \
  -o "$BUILD_DIR/StudyStatisticsCalculatorTests" \
  -framework Foundation

"$BUILD_DIR/StudyStatisticsCalculatorTests"

clang \
  -fobjc-arc \
  -mmacosx-version-min=13.0 \
  -I"$ROOT_DIR/Sources" \
  "$ROOT_DIR/Tests/StudyStatisticsWindowControllerTests.m" \
  "$ROOT_DIR/Sources/StudyHistoryStore.m" \
  "$ROOT_DIR/Sources/StudyStatisticsCalculator.m" \
  "$ROOT_DIR/Sources/StudyStatisticsWindowController.m" \
  -o "$BUILD_DIR/StudyStatisticsWindowControllerTests" \
  -framework Cocoa

"$BUILD_DIR/StudyStatisticsWindowControllerTests"

"$ROOT_DIR/Tests/WaitForProcessTests.sh"
