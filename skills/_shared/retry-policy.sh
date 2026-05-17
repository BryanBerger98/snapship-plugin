#!/usr/bin/env bash
# retry-policy.sh — decide whether an MCP failure is retry-able, and sleep
# the appropriate backoff before signalling go-for-retry. Pairs with
# `check-mcp-response.sh`: caller passes the failure REASON (stderr line)
# plus the count of attempts so far.
#
# Usage:
#   retry-policy.sh REASON ATTEMPT
#     REASON   — failure reason string (e.g. "mcp: error: rate-limit").
#     ATTEMPT  — count of failed attempts so far (1-based, positive int).
#
# Env:
#   SNAP_MCP_RETRY_MAX      — max retries allowed after the initial attempt
#                             (default 2 → up to 3 attempts total).
#   SNAP_MCP_RETRY_BASE_MS  — base backoff in ms; doubled per attempt
#                             (default 500 → 500ms, 1000ms, 2000ms, …).
#
# Behaviour (checked in order):
#   1. Non-retryable reason  → rc=1, stderr `retry-policy: non-retryable: <REASON>`.
#   2. Retryable but exhausted (ATTEMPT > MAX) → rc=1, stderr
#      `retry-policy: exhausted (ATTEMPT/MAX): <REASON>`.
#   3. Retryable + within budget → sleep BASE_MS * 2^(ATTEMPT-1) ms, rc=0.
#
# Retryable reasons (case-insensitive substring match):
#   rate-limit, ratelimit, timeout, network, transient,
#   server-error, 5xx, 502, 503, 504.
#
# Rationale: keeps retry *policy* deterministic and testable while the
# *mechanism* (re-invoking MCP) stays in the calling step — subprocesses
# cannot invoke MCP directly, so policy/mechanism must split.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "ERROR: retry-policy.sh REASON ATTEMPT" >&2
  exit 2
fi

REASON="$1"
ATTEMPT_RAW="$2"

if ! [[ "$ATTEMPT_RAW" =~ ^[0-9]+$ ]] || [ "$ATTEMPT_RAW" -lt 1 ]; then
  echo "ERROR: ATTEMPT must be a positive integer (got: $ATTEMPT_RAW)" >&2
  exit 2
fi

ATTEMPT="$ATTEMPT_RAW"
MAX="${SNAP_MCP_RETRY_MAX:-2}"
BASE_MS="${SNAP_MCP_RETRY_BASE_MS:-500}"

if ! [[ "$MAX" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SNAP_MCP_RETRY_MAX must be a non-negative integer (got: $MAX)" >&2
  exit 2
fi
if ! [[ "$BASE_MS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: SNAP_MCP_RETRY_BASE_MS must be a non-negative integer (got: $BASE_MS)" >&2
  exit 2
fi

reason_lc=$(printf '%s' "$REASON" | tr '[:upper:]' '[:lower:]')

retryable=0
for pat in 'rate-limit' 'ratelimit' 'timeout' 'network' 'transient' 'server-error' '5xx' '502' '503' '504'; do
  case "$reason_lc" in
    *"$pat"*) retryable=1; break ;;
  esac
done

if [ "$retryable" -eq 0 ]; then
  echo "retry-policy: non-retryable: $REASON" >&2
  exit 1
fi

if [ "$ATTEMPT" -gt "$MAX" ]; then
  echo "retry-policy: exhausted ($ATTEMPT/$MAX): $REASON" >&2
  exit 1
fi

# Backoff: BASE_MS * 2^(ATTEMPT-1). Bash arithmetic suffices for sane MAX.
delay_ms=$(( BASE_MS * (1 << (ATTEMPT - 1)) ))
delay_s=$(awk -v ms="$delay_ms" 'BEGIN { printf "%.3f", ms / 1000 }')

echo "retry-policy: retry $ATTEMPT/$MAX in ${delay_ms}ms (reason: $REASON)" >&2
sleep "$delay_s"
exit 0
