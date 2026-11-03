#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WAITER="$ROOT_DIR/scripts/wait_for_process.sh"
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/FocusBreakTimerWaitTests.XXXXXX")"
background_pid=""

cleanup() {
  if [ -n "$background_pid" ]; then
    kill "$background_pid" >/dev/null 2>&1 || true
    wait "$background_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

require_status() {
  expected=$1
  status_file=$2
  grep -q "^state=${expected}$" "$status_file" || {
    echo "FAIL: expected state=${expected} in $status_file" >&2
    exit 1
  }
}

run_expected_exit() {
  expected=$1
  shift
  set +e
  "$@"
  actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "FAIL: expected exit $expected, got $actual" >&2
    exit 1
  fi
}

completion_dir="$TEST_DIR/completion"
mkdir -p "$completion_dir"
sleep 1 &
background_pid=$!
printf '%s\n' "$background_pid" > "$completion_dir/process.pid"
printf 'started\n' > "$completion_dir/process.log"
run_expected_exit 0 "$WAITER" \
  --pid-file "$completion_dir/process.pid" \
  --log-file "$completion_dir/process.log" \
  --max-wait 8 \
  --stale-after 8 \
  --poll-interval 1
wait "$background_pid" >/dev/null 2>&1 || true
background_pid=""
require_status completed "$completion_dir/process.pid.wait-status"

stale_dir="$TEST_DIR/stale"
mkdir -p "$stale_dir"
sleep 10 &
background_pid=$!
printf '%s\n' "$background_pid" > "$stale_dir/process.pid"
printf 'started\n' > "$stale_dir/process.log"
run_expected_exit 3 "$WAITER" \
  --pid-file "$stale_dir/process.pid" \
  --log-file "$stale_dir/process.log" \
  --max-wait 8 \
  --stale-after 2 \
  --poll-interval 1
require_status stale "$stale_dir/process.pid.wait-status"
kill "$background_pid" >/dev/null 2>&1 || true
wait "$background_pid" >/dev/null 2>&1 || true
background_pid=""

timeout_dir="$TEST_DIR/timeout"
mkdir -p "$timeout_dir"
sleep 10 &
background_pid=$!
printf '%s\n' "$background_pid" > "$timeout_dir/process.pid"
printf 'started\n' > "$timeout_dir/process.log"
run_expected_exit 2 "$WAITER" \
  --pid-file "$timeout_dir/process.pid" \
  --log-file "$timeout_dir/process.log" \
  --max-wait 2 \
  --stale-after 0 \
  --poll-interval 1
require_status timed_out "$timeout_dir/process.pid.wait-status"
kill "$background_pid" >/dev/null 2>&1 || true
wait "$background_pid" >/dev/null 2>&1 || true
background_pid=""

invalid_dir="$TEST_DIR/invalid"
mkdir -p "$invalid_dir"
printf 'not-a-pid\n' > "$invalid_dir/process.pid"
run_expected_exit 4 "$WAITER" \
  --pid-file "$invalid_dir/process.pid" \
  --log-file "$invalid_dir/process.log" \
  --max-wait 2 \
  --stale-after 2 \
  --poll-interval 1
require_status invalid_pid "$invalid_dir/process.pid.wait-status"

echo "wait_for_process tests passed"
