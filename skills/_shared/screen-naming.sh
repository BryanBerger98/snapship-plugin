#!/usr/bin/env bash
# screen-naming.sh — render an exported screen file base-name from a
# naming_pattern by substituting the tokens shared by /wireframe and /design.
#
# Tokens: {story_id}, {screen_name}, {state}.
#
# Used by:
#   /wireframe → config.wireframes.naming_pattern (default "{story_id}-{screen_name}")
#   /design    → config.design.naming_pattern     (default "{story_id}-{screen_name}-design")
# The design default's "-design" suffix is plain literal text in the pattern,
# not a token, so the same substitution renders it naturally.
#
# Usage:
#   screen-naming.sh --context='{"story_id":"01-login","screen_name":"signup-screen","state":"empty"}'
#       → 01-login-signup-screen        (default pattern "{story_id}-{screen_name}")
#   screen-naming.sh --pattern='{story_id}/{screen_name}-{state}' --context='{...}'
#       → 01-login/signup-screen-empty
#
# When --pattern is omitted the pattern is read from config at the JSON path
# given by --config-key (default "wireframes.naming_pattern"), falling back to
# --default (or "{story_id}-{screen_name}") when absent.
#
# The rendered string is a file BASE-NAME (no extension); the caller appends
# the resolved export format. Unknown tokens left in the pattern are an error
# (exit 1) so a typo'd config surfaces instead of leaking literal braces.
#
# Exit codes: 0=ok, 1=invalid arg / unresolved token

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
CONTEXT=""
PATTERN_OVERRIDE=""
CONFIG_KEY="wireframes.naming_pattern"
DEFAULT_PATTERN="{story_id}-{screen_name}"

usage() {
  cat <<EOF
Usage: screen-naming.sh --context=JSON [OPTIONS]

Renders an exported screen file base-name from a naming_pattern.

Required:
  --context=JSON           Token values. Supported keys:
                             story_id, screen_name, state

Options:
  --pattern=TPL            Override pattern (default: config at --config-key
                             or --default)
  --config-key=PATH        Dotted config path read when --pattern is omitted
                             (default: wireframes.naming_pattern)
  --default=TPL            Fallback pattern when config has no value
                             (default: {story_id}-{screen_name})
  --project-root=PATH      Project root for config (default: \$PWD)
  -h, --help               Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --context=*)       CONTEXT="${1#--context=}" ;;
    --pattern=*)       PATTERN_OVERRIDE="${1#--pattern=}" ;;
    --config-key=*)    CONFIG_KEY="${1#--config-key=}" ;;
    --default=*)       DEFAULT_PATTERN="${1#--default=}" ;;
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$CONTEXT" ] && { echo "ERROR: --context required" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

if ! echo "$CONTEXT" | jq empty 2>/dev/null; then
  echo "ERROR: --context must be valid JSON" >&2
  exit 1
fi

# Resolve pattern: explicit override > config > built-in default.
if [ -n "$PATTERN_OVERRIDE" ]; then
  tpl="$PATTERN_OVERRIDE"
else
  CONFIG="{}"
  if [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
    CONFIG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
  fi
  tpl=$(echo "$CONFIG" | jq -r --arg k "$CONFIG_KEY" --arg d "$DEFAULT_PATTERN" 'getpath($k | split(".")) // $d')
  [ -z "$tpl" ] && tpl="$DEFAULT_PATTERN"
fi

story_id=$(echo "$CONTEXT"   | jq -r '.story_id // ""')
screen_name=$(echo "$CONTEXT" | jq -r '.screen_name // ""')
state=$(echo "$CONTEXT"       | jq -r '.state // ""')

out="$tpl"
out="${out//\{story_id\}/$story_id}"
out="${out//\{screen_name\}/$screen_name}"
out="${out//\{state\}/$state}"

# Any remaining {token} means an unknown placeholder — fail loudly.
if [[ "$out" == *'{'*'}'* ]]; then
  echo "ERROR: unresolved token(s) in naming_pattern: '$out'" >&2
  exit 1
fi

printf '%s\n' "$out"
