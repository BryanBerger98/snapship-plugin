#!/usr/bin/env bash
# Resolve /design mode (ds-init|ds-update|mockup|ambiguous|none) from signals.
#
# Signals checked, by precedence:
#   1. DS binding empty + bundled/specs YAML present                       → ds-init
#   2. DS binding set + specs_hash changed vs .design-cache.json           → ds-update
#   3. feature_id has tickets.json with ≥1 UI ticket                       → mockup
#
# Multiple matches → "ambiguous" (skill falls back to AskUserQuestion).
# No matches → "none" (skill aborts with explanatory message).
#
# Usage:
#   design-mode-resolver.sh \
#     --project-root=DIR \
#     --ds-binding-set=true|false \
#     --specs-dir=PATH \
#     --cache-file=PATH \
#     --feature-id=ID
#
# Output: single token on stdout (ds-init|ds-update|mockup|ambiguous|none).
# Exit 0 always (caller decides what to do with the token).

set -uo pipefail

PROJECT_ROOT=""
DS_BINDING_SET="false"
SPECS_DIR=""
CACHE_FILE=""
FEATURE_ID=""

for arg in "$@"; do
  case "$arg" in
    --project-root=*)    PROJECT_ROOT="${arg#--project-root=}" ;;
    --ds-binding-set=*)  DS_BINDING_SET="${arg#--ds-binding-set=}" ;;
    --specs-dir=*)       SPECS_DIR="${arg#--specs-dir=}" ;;
    --cache-file=*)      CACHE_FILE="${arg#--cache-file=}" ;;
    --feature-id=*)      FEATURE_ID="${arg#--feature-id=}" ;;
    -h|--help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

[ -n "$PROJECT_ROOT" ] || { echo "ERROR: --project-root required" >&2; exit 2; }

matches=()

# --- Signal 1: ds-init ---------------------------------------------------
if [ "$DS_BINDING_SET" = "false" ] && [ -n "$SPECS_DIR" ]; then
  if [ -d "$PROJECT_ROOT/$SPECS_DIR" ]; then
    count=$(find "$PROJECT_ROOT/$SPECS_DIR" -maxdepth 1 -name "*.yaml" 2>/dev/null | wc -l | tr -d ' ')
    if [ "$count" -gt 0 ]; then
      matches+=("ds-init")
    fi
  fi
fi

# --- Signal 2: ds-update -------------------------------------------------
if [ "$DS_BINDING_SET" = "true" ] && [ -n "$CACHE_FILE" ] && [ -n "$SPECS_DIR" ]; then
  cache_path="$PROJECT_ROOT/$CACHE_FILE"
  specs_dir_path="$PROJECT_ROOT/$SPECS_DIR"
  if [ -f "$cache_path" ] && [ -d "$specs_dir_path" ]; then
    prev_hash=$(jq -r '.specs_hash // ""' "$cache_path" 2>/dev/null)
    specs_files=$(find "$specs_dir_path" -maxdepth 1 -name "*.yaml" 2>/dev/null | sort)
    if [ -n "$specs_files" ]; then
      # shellcheck disable=SC2086
      curr_hash=$(cat $specs_files | shasum -a 256 | awk '{print $1}')
      if [ -n "$prev_hash" ] && [ "$prev_hash" != "$curr_hash" ]; then
        matches+=("ds-update")
      fi
    fi
  fi
fi

# --- Signal 3: mockup ---------------------------------------------------
if [ -n "$FEATURE_ID" ]; then
  tickets_file="$PROJECT_ROOT/.claude/product/features/$FEATURE_ID/tickets.json"
  if [ -f "$tickets_file" ]; then
    ui_count=$(jq '[.tickets[]
      | select(
          ((.files // []) | map(test("\\.(tsx|jsx|vue|svelte|astro|html|css|scss)$")) | any)
          or
          ((.title // "") | test("screen|page|view|modal|form"; "i"))
        )
      ] | length' "$tickets_file" 2>/dev/null || echo 0)
    if [ "$ui_count" -gt 0 ]; then
      matches+=("mockup")
    fi
  fi
fi

# --- Resolve ------------------------------------------------------------
case "${#matches[@]}" in
  0)  echo "none" ;;
  1)  echo "${matches[0]}" ;;
  *)  echo "ambiguous" ;;
esac

exit 0
