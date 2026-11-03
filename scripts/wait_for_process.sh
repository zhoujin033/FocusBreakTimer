#!/usr/bin/env bash
set -u

usage() {
  cat <<'EOF'
Usage: wait_for_process.sh --pid-file PATH --log-file PATH [options]

Wait for a process recorded in a PID file without polling from the caller.

Options:
  --max-wait SECONDS       Stop after this many seconds (default: 3600, 0 disables).
  --stale-after SECONDS    Stop when the log is unchanged this long (default: 300, 0 disables).
  --poll-interval SECONDS  Seconds between checks (default: 5).
  --status-file PATH       Write the final status here (default: PID_FILE.wait-status).
  -h, --help               Show this help.

Exit codes:
  0  Process exited.
  2  Maximum wait time reached.
  3  Log file was stale.
  4  PID file or PID was invalid.
EOF
}

pid_file=""
log_file=""
status_file=""
max_wait=3600
stale_after=300
poll_interval=5

is_nonnegative_integer() {
  case "$1" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --pid-file)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      pid_file=$2
      shift 2
      ;;
    --log-file)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      log_file=$2
      shift 2
      ;;
    --max-wait)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      max_wait=$2
      shift 2
      ;;
    --stale-after)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      stale_after=$2
      shift 2
      ;;
    --poll-interval)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      poll_interval=$2
      shift 2
      ;;
    --status-file)
      [ "$#" -ge 2 ] || { usage >&2; exit 4; }
      status_file=$2
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 4
      ;;
  esac
done

if [ -z "$pid_file" ] || [ -z "$log_file" ]; then
  echo "Both --pid-file and --log-file are required." >&2
  usage >&2
  exit 4
fi
if ! is_nonnegative_integer "$max_wait" ||
   ! is_nonnegative_integer "$stale_after" ||
   ! is_nonnegative_integer "$poll_interval" ||
   [ "$poll_interval" -eq 0 ]; then
  echo "Wait values must be nonnegative integers, and --poll-interval must be greater than zero." >&2
  exit 4
fi
if [ -z "$status_file" ]; then
  status_file="${pid_file}.wait-status"
fi

write_status() {
  state=$1
  reason=$2
  elapsed=$3
  finished_at=$(date +%s)
  status_dir=$(dirname "$status_file")
  status_name=$(basename "$status_file")
  temporary_status="${status_dir}/.${status_name}.$$"
  {
    printf 'state=%s\n' "$state"
    printf 'reason=%s\n' "$reason"
    printf 'pid=%s\n' "${pid:-}"
    printf 'elapsed_seconds=%s\n' "$elapsed"
    printf 'finished_at=%s\n' "$finished_at"
    printf 'pid_file=%s\n' "$pid_file"
    printf 'log_file=%s\n' "$log_file"
  } > "$temporary_status"
  mv "$temporary_status" "$status_file"
}

finish() {
  exit_code=$1
  state=$2
  reason=$3
  now=$(date +%s)
  elapsed=$((now - started_at))
  write_status "$state" "$reason" "$elapsed"
  printf '%s: %s (pid=%s, elapsed=%ss)\n' "$state" "$reason" "${pid:-unknown}" "$elapsed"
  exit "$exit_code"
}

file_modified_at() {
  target=$1
  if [ ! -e "$target" ]; then
    return 1
  fi
  if stat -f '%m' "$target" >/dev/null 2>&1; then
    stat -f '%m' "$target"
  else
    stat -c '%Y' "$target"
  fi
}

started_at=$(date +%s)
pid=""
trap 'finish 130 interrupted signal' INT TERM

if [ ! -r "$pid_file" ]; then
  finish 4 invalid_pid "PID file is missing or unreadable"
fi
IFS= read -r pid < "$pid_file" || true
case "$pid" in
  ''|*[!0-9]*) finish 4 invalid_pid "PID file does not contain a numeric PID" ;;
esac
if [ "$pid" -le 1 ]; then
  finish 4 invalid_pid "PID must be greater than 1"
fi

while true; do
  now=$(date +%s)
  elapsed=$((now - started_at))

  if ! kill -0 "$pid" >/dev/null 2>&1; then
    finish 0 completed "process exited"
  fi

  if [ "$max_wait" -gt 0 ] && [ "$elapsed" -ge "$max_wait" ]; then
    finish 2 timed_out "maximum wait time reached"
  fi

  if [ "$stale_after" -gt 0 ]; then
    if modified_at=$(file_modified_at "$log_file"); then
      inactive_for=$((now - modified_at))
    else
      inactive_for=$elapsed
    fi
    if [ "$inactive_for" -ge "$stale_after" ]; then
      finish 3 stale "log file has not changed for ${inactive_for}s"
    fi
  fi

  sleep "$poll_interval"
done
