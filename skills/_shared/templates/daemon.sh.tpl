#!/usr/bin/env bash
# {{daemon_name}} — artysan loop daemon
#
# Runs `{{daemon_command}}` every {{daemon_interval_s}}s with structured
# logging, lock-file mutual exclusion, and graceful SIGTERM shutdown.
# Generated from skills/_shared/templates/daemon.sh.tpl by artysan setup.
#
# Variables (substituted at install time):
#   {{daemon_name}}              short slug used in logs/lock files
#   {{daemon_command}}           shell command to run each tick
#   {{daemon_interval_s}}        seconds between ticks (integer >= 1)
#   {{daemon_log_dir}}           absolute path of log dir
#   {{daemon_run_dir}}           absolute path of run dir (for pid/lock)
#   {{daemon_max_consecutive_failures}}  bail after N failures (integer >= 1)

set -euo pipefail

NAME="{{daemon_name}}"
CMD="{{daemon_command}}"
INTERVAL_S="{{daemon_interval_s}}"
LOG_DIR="{{daemon_log_dir}}"
RUN_DIR="{{daemon_run_dir}}"
MAX_FAIL="{{daemon_max_consecutive_failures}}"

LOG_FILE="${LOG_DIR}/${NAME}.log"
PID_FILE="${RUN_DIR}/${NAME}.pid"
LOCK_FILE="${RUN_DIR}/${NAME}.lock"

mkdir -p "$LOG_DIR" "$RUN_DIR"

log() {
  local level="$1"; shift
  printf '[%s] [%s] [%s] %s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$NAME" "$level" "$*" >> "$LOG_FILE"
}

acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    log error "another instance holds $LOCK_FILE — exiting"
    exit 1
  fi
  echo "$$" > "$PID_FILE"
}

release_lock() {
  rm -f "$PID_FILE" "$LOCK_FILE"
}

shutdown() {
  log info "received SIGTERM/SIGINT, exiting cleanly after current tick"
  release_lock
  exit 0
}

trap shutdown SIGTERM SIGINT

acquire_lock
log info "started (interval=${INTERVAL_S}s, pid=$$)"

consecutive_fail=0

while true; do
  start=$(date +%s)
  if eval "$CMD" >> "$LOG_FILE" 2>&1; then
    log info "tick ok"
    consecutive_fail=0
  else
    rc=$?
    consecutive_fail=$((consecutive_fail + 1))
    log error "tick failed (rc=${rc}, consecutive_fail=${consecutive_fail}/${MAX_FAIL})"
    if [ "$consecutive_fail" -ge "$MAX_FAIL" ]; then
      log error "max consecutive failures reached, bailing out"
      release_lock
      exit 2
    fi
  fi
  end=$(date +%s)
  elapsed=$((end - start))
  sleep_for=$((INTERVAL_S - elapsed))
  [ "$sleep_for" -gt 0 ] && sleep "$sleep_for" || log warn "tick took ${elapsed}s (>= interval ${INTERVAL_S}s)"
done
