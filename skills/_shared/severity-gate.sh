#!/usr/bin/env bash
# severity-gate.sh — decide whether a reviewer's findings block the develop cycle.
#
# A reviewer blocks the cycle when its worst finding severity is >= its
# configured threshold. Severity ordering (low→high):
#   none < info < minor < major < critical
# `none` means "no finding" and always passes (it sits below every threshold).
#
# Modes:
#   verdict (default) — prints "block" or "pass" on stdout, exit 0.
#   gate              — silent; exit 0 = block, exit 10 = pass.
#                       (exit 1/2 reserved for usage/validation errors)
#
# Usage:
#   severity-gate.sh --severity=major --threshold=minor            # -> block
#   severity-gate.sh --severity=info  --threshold=minor            # -> pass
#   severity-gate.sh --severity=none  --threshold=info             # -> pass
#   severity-gate.sh --severity=major --threshold=minor --mode=gate; echo $?

set -euo pipefail

SEVERITY=""
THRESHOLD=""
MODE="verdict"

usage() {
  cat <<EOF
Usage: severity-gate.sh --severity=LEVEL --threshold=LEVEL [--mode=verdict|gate]

Decides if a reviewer blocks the develop cycle: blocks when severity >= threshold.

Levels (low→high): none info minor major critical

Required:
  --severity=LEVEL    Reviewer's worst finding severity.
  --threshold=LEVEL   Reviewer's configured severity_threshold.

Optional:
  --mode=verdict      Print "block"|"pass" on stdout, exit 0 (default).
  --mode=gate         Silent; exit 0 = block, exit 10 = pass.
  -h, --help          Show this help.

Exit codes:
  0   verdict mode: always; gate mode: blocks
  10  gate mode: passes (does not block)
  1   invalid argument / unknown level
  2   missing required argument
EOF
}

# Map a severity level to a numeric rank. Unknown → empty (caller errors).
rank() {
  case "$1" in
    none)     printf '0' ;;
    info)     printf '1' ;;
    minor)    printf '2' ;;
    major)    printf '3' ;;
    critical) printf '4' ;;
    *)        printf '' ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --severity=*)  SEVERITY="${1#--severity=}" ;;
    --threshold=*) THRESHOLD="${1#--threshold=}" ;;
    --mode=*)      MODE="${1#--mode=}" ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[[ -z "$SEVERITY" ]]  && { echo "ERROR: --severity required" >&2; exit 2; }
[[ -z "$THRESHOLD" ]] && { echo "ERROR: --threshold required" >&2; exit 2; }

case "$MODE" in
  verdict|gate) ;;
  *) echo "ERROR: --mode must be verdict|gate" >&2; exit 1 ;;
esac

sev_rank="$(rank "$SEVERITY")"
thr_rank="$(rank "$THRESHOLD")"

[[ -z "$sev_rank" ]]  && { echo "ERROR: invalid severity: ${SEVERITY}" >&2; exit 1; }
[[ -z "$thr_rank" ]]  && { echo "ERROR: invalid threshold: ${THRESHOLD}" >&2; exit 1; }

if [[ "$sev_rank" -ge "$thr_rank" ]]; then
  blocks=1
else
  blocks=0
fi

if [[ "$MODE" = "verdict" ]]; then
  if [[ "$blocks" -eq 1 ]]; then
    printf 'block\n'
  else
    printf 'pass\n'
  fi
  exit 0
fi

# gate mode
if [[ "$blocks" -eq 1 ]]; then
  exit 0
fi
exit 10
