#!/usr/bin/env bash
# apply-naming.sh — render feature_id / branch / commit names from config.naming.*
# Reads config via load-config.sh, applies template + slug rules.
#
# Usage:
#   apply-naming.sh --type=feature_id --context='{"nn":"01","name":"User Authentication"}'
#       → 01-user-authentication
#   apply-naming.sh --type=branch --context='{"type":"feat","ticket_id":"AUTH-3","slug":"login-form"}'
#       → feat/AUTH-3-login-form
#   apply-naming.sh --type=commit --context='{"type":"feat","scope":"auth","message":"add login"}'
#       → feat(auth): add login
#
# Exit codes: 0=ok, 1=invalid arg / missing template var

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"
TYPE=""
CONTEXT=""

usage() {
  cat <<EOF
Usage: apply-naming.sh --type=TYPE --context=JSON [OPTIONS]

Renders names according to config.naming templates.

Required:
  --type=feature_id|branch|commit  Naming type
  --context=JSON                    Variables for template substitution

Vars per type:
  feature_id  {nn} (zero-padded number) {name} (slugified, truncated)
              Format hardcoded: NN-kebab
  branch      {type} {ticket_id} {slug} (template = config.naming.branch_pattern)
  commit      {type} {scope} {message} (template = config.naming.commit_pattern)

Options:
  --project-root=PATH      Project root for config (default: \$PWD)
  --slug-max-length=N      Override config.naming.feature_slug_max_length
  --branch-pattern=TPL     Override branch template
  --commit-pattern=TPL     Override commit template
  -h, --help               Show this help
EOF
}

SLUG_MAX_OVERRIDE=""
BRANCH_PATTERN_OVERRIDE=""
COMMIT_PATTERN_OVERRIDE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --type=*)              TYPE="${1#--type=}" ;;
    --context=*)           CONTEXT="${1#--context=}" ;;
    --project-root=*)      PROJECT_ROOT="${1#--project-root=}" ;;
    --slug-max-length=*)   SLUG_MAX_OVERRIDE="${1#--slug-max-length=}" ;;
    --branch-pattern=*)    BRANCH_PATTERN_OVERRIDE="${1#--branch-pattern=}" ;;
    --commit-pattern=*)    COMMIT_PATTERN_OVERRIDE="${1#--commit-pattern=}" ;;
    -h|--help)             usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$TYPE" ]    && { echo "ERROR: --type required" >&2; exit 1; }
[ -z "$CONTEXT" ] && { echo "ERROR: --context required" >&2; exit 1; }

case "$TYPE" in
  feature_id|branch|commit) ;;
  *) echo "ERROR: --type must be feature_id|branch|commit" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

if ! echo "$CONTEXT" | jq empty 2>/dev/null; then
  echo "ERROR: --context must be valid JSON" >&2
  exit 1
fi

# Slugify: lowercase, ASCII-fold accents, replace non-alphanumeric with -, collapse repeats, trim, truncate.
slugify() {
  local input="$1"
  local maxlen="${2:-0}"
  local out

  # ASCII-fold via tr (best-effort) + iconv if available
  if command -v iconv >/dev/null 2>&1; then
    out=$(printf '%s' "$input" | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null || printf '%s' "$input")
  else
    out="$input"
  fi

  out=$(printf '%s' "$out" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E "s/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g")

  if [ "$maxlen" -gt 0 ] && [ "${#out}" -gt "$maxlen" ]; then
    out="${out:0:$maxlen}"
    out="${out%-}"
  fi

  printf '%s' "$out"
}

# Resolve config (only if needed)
needs_config=false
case "$TYPE" in
  feature_id) [ -z "$SLUG_MAX_OVERRIDE" ] && needs_config=true ;;
  branch)     [ -z "$BRANCH_PATTERN_OVERRIDE" ] && needs_config=true ;;
  commit)     [ -z "$COMMIT_PATTERN_OVERRIDE" ] && needs_config=true ;;
esac

CONFIG="{}"
if [ "$needs_config" = true ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
    CONFIG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
  fi
fi

case "$TYPE" in
  feature_id)
    nn=$(echo "$CONTEXT" | jq -r '.nn // ""')
    name=$(echo "$CONTEXT" | jq -r '.name // ""')
    [ -z "$nn" ]   && { echo "ERROR: context.nn required for feature_id" >&2; exit 1; }
    [ -z "$name" ] && { echo "ERROR: context.name required for feature_id" >&2; exit 1; }
    if ! [[ "$nn" =~ ^[0-9]+$ ]]; then
      echo "ERROR: context.nn must be integer" >&2
      exit 1
    fi
    # Zero-pad to 2 digits
    nn=$(printf '%02d' "$nn")
    if [ -n "$SLUG_MAX_OVERRIDE" ]; then
      maxlen="$SLUG_MAX_OVERRIDE"
    else
      maxlen=$(echo "$CONFIG" | jq -r '.naming.feature_slug_max_length // 40')
    fi
    slug=$(slugify "$name" "$maxlen")
    [ -z "$slug" ] && { echo "ERROR: name produced empty slug" >&2; exit 1; }
    printf '%s-%s\n' "$nn" "$slug"
    ;;

  branch)
    if [ -n "$BRANCH_PATTERN_OVERRIDE" ]; then
      tpl="$BRANCH_PATTERN_OVERRIDE"
    else
      tpl=$(echo "$CONFIG" | jq -r '.naming.branch_pattern // "{type}/{ticket_id}-{slug}"')
    fi
    btype=$(echo "$CONTEXT" | jq -r '.type // ""')
    tid=$(echo "$CONTEXT"   | jq -r '.ticket_id // ""')
    slug_in=$(echo "$CONTEXT" | jq -r '.slug // ""')

    [ -z "$btype" ]   && { echo "ERROR: context.type required for branch" >&2; exit 1; }
    [ -z "$tid" ]     && { echo "ERROR: context.ticket_id required for branch" >&2; exit 1; }
    [ -z "$slug_in" ] && { echo "ERROR: context.slug required for branch" >&2; exit 1; }

    slug=$(slugify "$slug_in")

    out="$tpl"
    out="${out//\{type\}/$btype}"
    out="${out//\{ticket_id\}/$tid}"
    out="${out//\{slug\}/$slug}"
    printf '%s\n' "$out"
    ;;

  commit)
    if [ -n "$COMMIT_PATTERN_OVERRIDE" ]; then
      tpl="$COMMIT_PATTERN_OVERRIDE"
    else
      tpl=$(echo "$CONFIG" | jq -r '.naming.commit_pattern // "{type}({scope}): {message}"')
    fi
    ctype=$(echo "$CONTEXT"   | jq -r '.type // ""')
    cscope=$(echo "$CONTEXT"  | jq -r '.scope // ""')
    cmsg=$(echo "$CONTEXT"    | jq -r '.message // ""')

    [ -z "$ctype" ] && { echo "ERROR: context.type required for commit" >&2; exit 1; }
    [ -z "$cmsg" ]  && { echo "ERROR: context.message required for commit" >&2; exit 1; }

    out="$tpl"
    out="${out//\{type\}/$ctype}"
    out="${out//\{scope\}/$cscope}"
    out="${out//\{message\}/$cmsg}"
    # Strip empty scope artifact: "(): " or "()" — common when scope is empty
    out=$(printf '%s' "$out" | sed -E 's/\(\): /: /; s/\(\)//')
    printf '%s\n' "$out"
    ;;
esac
