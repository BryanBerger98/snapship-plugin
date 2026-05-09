#!/usr/bin/env bash
# parse-agent-output.sh — Parse subagent output into normalized {severity, feedback_md} JSON.
#
# Subagents (code-reviewer-{technical,functional,security,qa}, developer) end their
# response with a single ```json fenced block containing {severity, feedback_md}.
# This script extracts that fence, validates the schema, and provides aggregation
# helpers for combining multiple reviewers' outputs.
#
# Subcommands:
#   parse [--file=PATH]                 Extract last ```json fence from stdin or file,
#                                       emit normalized {severity, feedback_md}.
#   rank SEV                            Print numeric rank: none=0, info=1, minor=2,
#                                       major=3, critical=4.
#   max SEV [SEV ...]                   Print highest severity from list.
#   aggregate FILE [FILE ...]           Parse each file, emit {severity: max,
#                                       feedback_md: concatenated}.
#
# Exit codes:
#   0 = success
#   1 = invalid input (missing fence, malformed JSON, missing fields, bad severity)
#   2 = usage error
#
# Usage: parse-agent-output.sh <subcommand> [args]

set -euo pipefail

VALID_SEVERITIES="none info minor major critical"

usage() {
  cat <<EOF
Usage: parse-agent-output.sh <subcommand> [args]

Subcommands:
  parse [--file=PATH]            Extract last \`\`\`json fence from stdin or file,
                                 emit normalized {severity, feedback_md} JSON.
  rank SEV                       Print numeric rank (none=0..critical=4).
  max SEV [SEV ...]              Print highest severity from list.
  aggregate FILE [FILE ...]      Parse each file, emit {severity:max, feedback_md:concat}.

  -h, --help                     Show this help.

Severity scale: none < info < minor < major < critical
EOF
}

severity_rank() {
  case "$1" in
    none)     echo 0 ;;
    info)     echo 1 ;;
    minor)    echo 2 ;;
    major)    echo 3 ;;
    critical) echo 4 ;;
    *) echo "ERROR: invalid severity: $1" >&2; return 1 ;;
  esac
}

severity_from_rank() {
  case "$1" in
    0) echo none ;;
    1) echo info ;;
    2) echo minor ;;
    3) echo major ;;
    4) echo critical ;;
    *) echo "ERROR: invalid rank: $1" >&2; return 1 ;;
  esac
}

# Extract content of the LAST ```json ... ``` fence from stdin.
# Prints the JSON body (no fence markers). Empty if no fence found.
extract_last_json_fence() {
  awk '
    BEGIN { in_fence = 0 }
    /^```json[[:space:]]*$/ {
      in_fence = 1
      buf = ""
      next
    }
    /^```[[:space:]]*$/ {
      if (in_fence) {
        last = buf
        in_fence = 0
      }
      next
    }
    in_fence {
      buf = buf $0 "\n"
    }
    END {
      if (in_fence) {
        last = buf
      }
      printf "%s", last
    }
  '
}

# Parse: read stdin (or --file=PATH), extract last json fence, validate, emit normalized.
cmd_parse() {
  local file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --file=*) file="${1#--file=}" ;;
      -h|--help) usage; return 0 ;;
      *) echo "ERROR: unknown arg: $1" >&2; return 2 ;;
    esac
    shift
  done

  local raw
  if [ -n "$file" ]; then
    [ -f "$file" ] || { echo "ERROR: file not found: $file" >&2; return 1; }
    raw=$(extract_last_json_fence < "$file")
  else
    raw=$(extract_last_json_fence)
  fi

  if [ -z "$raw" ]; then
    echo "ERROR: no \`\`\`json fence found in input" >&2
    return 1
  fi

  if ! echo "$raw" | jq empty 2>/dev/null; then
    echo "ERROR: malformed JSON in fence" >&2
    return 1
  fi

  local severity feedback_md
  severity=$(echo "$raw" | jq -r '.severity // empty')
  feedback_md=$(echo "$raw" | jq -r '.feedback_md // empty')

  if [ -z "$severity" ]; then
    echo "ERROR: missing 'severity' field" >&2
    return 1
  fi

  case " $VALID_SEVERITIES " in
    *" $severity "*) ;;
    *) echo "ERROR: invalid severity: '$severity' (expected: $VALID_SEVERITIES)" >&2; return 1 ;;
  esac

  if [ -z "$feedback_md" ]; then
    echo "ERROR: missing 'feedback_md' field" >&2
    return 1
  fi

  jq -n --arg s "$severity" --arg f "$feedback_md" '{severity: $s, feedback_md: $f}'
}

cmd_rank() {
  [ $# -eq 1 ] || { echo "ERROR: rank requires exactly one severity arg" >&2; return 2; }
  severity_rank "$1"
}

cmd_max() {
  [ $# -ge 1 ] || { echo "ERROR: max requires at least one severity arg" >&2; return 2; }
  local max_rank=0 r
  for s in "$@"; do
    r=$(severity_rank "$s") || return 1
    if [ "$r" -gt "$max_rank" ]; then
      max_rank="$r"
    fi
  done
  severity_from_rank "$max_rank"
}

cmd_aggregate() {
  [ $# -ge 1 ] || { echo "ERROR: aggregate requires at least one file arg" >&2; return 2; }

  local max_rank=0 r parsed sev fb
  local combined_md=""

  for file in "$@"; do
    [ -f "$file" ] || { echo "ERROR: file not found: $file" >&2; return 1; }
    if ! parsed=$(cmd_parse --file="$file"); then
      echo "ERROR: failed to parse: $file" >&2
      return 1
    fi
    sev=$(echo "$parsed" | jq -r '.severity')
    fb=$(echo "$parsed" | jq -r '.feedback_md')

    r=$(severity_rank "$sev")
    [ "$r" -gt "$max_rank" ] && max_rank="$r"

    if [ -z "$combined_md" ]; then
      combined_md="$fb"
    else
      combined_md="${combined_md}"$'\n\n---\n\n'"${fb}"
    fi
  done

  local agg_sev
  agg_sev=$(severity_from_rank "$max_rank")

  jq -n --arg s "$agg_sev" --arg f "$combined_md" '{severity: $s, feedback_md: $f}'
}

# Main dispatch
[ $# -ge 1 ] || { usage >&2; exit 2; }

case "$1" in
  parse)     shift; cmd_parse "$@" ;;
  rank)      shift; cmd_rank "$@" ;;
  max)       shift; cmd_max "$@" ;;
  aggregate) shift; cmd_aggregate "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $1" >&2; usage >&2; exit 2 ;;
esac
