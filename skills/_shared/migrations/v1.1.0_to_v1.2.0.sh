#!/usr/bin/env bash
# v1.1.0_to_v1.2.0.sh — Hierarchy redesign (Epic / User Story / Task / Bug).
#
# Idempotent (re-run safe). Reads:
#   SNAP_PROJECT_ROOT             (required) repo root
#   SNAP_DECISIONS_JSON           (optional) user decisions JSON
#     { "drop_tickets_cache": "confirm" | "skip",
#       "rename_env":         "auto"    | "skip" }
#   SNAP_DRY_RUN=true             (optional) print actions only, no fs change
#
# Steps :
#   1. Rename snapship.config.json → snap.config.json (filesystem)
#   2. Rename .env.snapship       → .env.snap
#   3. Rename .snap/features/     → .snap/stories/
#   4. Migrate each .snap/stories/<id>/meta.json :
#        - feature_id → story_id
#        - drop epic_link
#        - add parent_epic_id: null  (user fills later)
#        - drop story_type "feature" → "user-story" (heuristic on existing rows)
#   5. Drop .snap/tickets/ per drop_tickets_cache decision (default: confirm)
#   6. Bump snap.config.json.version → 1.2
#
# Exit 0 = success (including no-op), 1 = fail.

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
DECISIONS="${SNAP_DECISIONS_JSON:-}"
[ -z "$DECISIONS" ] && DECISIONS='{}'
DRY_RUN="${SNAP_DRY_RUN:-false}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }
echo "$DECISIONS" | jq empty 2>/dev/null || { echo "ERROR: SNAP_DECISIONS_JSON invalid" >&2; exit 1; }

DEC_DROP_TICKETS=$(echo "$DECISIONS" | jq -r '.drop_tickets_cache // "confirm"')
DEC_RENAME_ENV=$(echo "$DECISIONS" | jq -r '.rename_env // "auto"')

say() { printf '%s\n' "$*"; }
log() { printf '  %s\n' "$*"; }
do_mv() {
  local src="$1" dst="$2"
  if [ "$DRY_RUN" = "true" ]; then
    log "DRY: mv '${src}' → '${dst}'"
  else
    mv "$src" "$dst"
    log "✓ ${src} → ${dst}"
  fi
}

say "→ Migration v1.1.0 → v1.2.0  (hierarchy redesign)"
say "  project_root        : ${PROJECT_ROOT}"
say "  drop_tickets_cache  : ${DEC_DROP_TICKETS}"
say "  rename_env          : ${DEC_RENAME_ENV}"
say "  dry_run             : ${DRY_RUN}"

OLD_CFG="${PROJECT_ROOT}/snapship.config.json"
NEW_CFG="${PROJECT_ROOT}/snap.config.json"
OLD_ENV="${PROJECT_ROOT}/.env.snapship"
NEW_ENV="${PROJECT_ROOT}/.env.snap"
OLD_FEATURES="${PROJECT_ROOT}/.snap/features"
NEW_STORIES="${PROJECT_ROOT}/.snap/stories"
OLD_TICKETS="${PROJECT_ROOT}/.snap/tickets"

# --- 1. Rename snapship.config.json → snap.config.json -------------------
if [ -f "$OLD_CFG" ] && [ ! -f "$NEW_CFG" ]; then
  do_mv "$OLD_CFG" "$NEW_CFG"
elif [ -f "$OLD_CFG" ] && [ -f "$NEW_CFG" ]; then
  say "⚠ Both snapship.config.json AND snap.config.json present — leaving as-is, user resolves manually."
elif [ ! -f "$OLD_CFG" ] && [ ! -f "$NEW_CFG" ]; then
  say "✓ No config file present — nothing to rename."
else
  log "✓ snap.config.json already present — skip rename."
fi

# --- 2. Rename .env.snapship → .env.snap ---------------------------------
if [ "$DEC_RENAME_ENV" != "skip" ]; then
  if [ -f "$OLD_ENV" ] && [ ! -f "$NEW_ENV" ]; then
    do_mv "$OLD_ENV" "$NEW_ENV"
  elif [ -f "$OLD_ENV" ] && [ -f "$NEW_ENV" ]; then
    say "⚠ Both .env.snapship AND .env.snap present — leaving as-is, user resolves manually."
  else
    log "✓ .env rename already applied or absent."
  fi
else
  say "→ env rename skipped (decision)"
fi

# --- 3. Rename .snap/features/ → .snap/stories/ --------------------------
if [ -d "$OLD_FEATURES" ] && [ ! -d "$NEW_STORIES" ]; then
  do_mv "$OLD_FEATURES" "$NEW_STORIES"
elif [ -d "$OLD_FEATURES" ] && [ -d "$NEW_STORIES" ]; then
  say "⚠ Both .snap/features/ AND .snap/stories/ present — merge manually then re-run."
  exit 1
elif [ ! -d "$OLD_FEATURES" ] && [ ! -d "$NEW_STORIES" ]; then
  say "✓ No stories dir to rename."
else
  log "✓ .snap/stories/ already present — skip rename."
fi

# --- 4. Migrate each meta.json -------------------------------------------
if [ -d "$NEW_STORIES" ]; then
  shopt -s nullglob
  for STORY_DIR in "${NEW_STORIES}"/*/; do
    [ -d "$STORY_DIR" ] || continue
    SID=$(basename "$STORY_DIR")
    META="${STORY_DIR}meta.json"
    [ -f "$META" ] || { log "skip ${SID} (no meta.json)"; continue; }

    HAS_FEATURE_ID=$(jq 'has("feature_id")' "$META")
    HAS_STORY_ID=$(jq 'has("story_id")' "$META")

    if [ "$HAS_STORY_ID" = "true" ] && [ "$HAS_FEATURE_ID" = "false" ]; then
      log "✓ ${SID}/meta.json already migrated"
      continue
    fi

    if [ "$DRY_RUN" = "true" ]; then
      log "DRY: migrate ${SID}/meta.json (feature_id→story_id, drop epic_link, add parent_epic_id)"
      continue
    fi

    tmp=$(mktemp)
    jq '
      (if has("feature_id") and (has("story_id") | not)
        then . + {story_id: .feature_id} | del(.feature_id)
        else . end)
      | del(.epic_link)
      | (if has("parent_epic_id") | not then . + {parent_epic_id: null} else . end)
    ' "$META" > "$tmp" && mv "$tmp" "$META"
    log "✓ ${SID}/meta.json migrated"
  done
  shopt -u nullglob
fi

# --- 5. Drop .snap/tickets/ ---------------------------------------------
if [ -d "$OLD_TICKETS" ]; then
  case "$DEC_DROP_TICKETS" in
    confirm)
      if [ "$DRY_RUN" = "true" ]; then
        say "DRY: would trash ${OLD_TICKETS} (tracker = single source in v1.2)"
      else
        if command -v trash >/dev/null 2>&1; then
          trash "$OLD_TICKETS"
          log "✓ .snap/tickets/ trashed (backup contains copy)"
        else
          say "⚠ trash unavailable — ${OLD_TICKETS} left in place. Remove manually."
        fi
      fi
      ;;
    skip)
      say "→ .snap/tickets/ kept (decision=skip). Cache no longer read by skills in v1.2."
      ;;
    *)
      echo "ERROR: invalid drop_tickets_cache decision: ${DEC_DROP_TICKETS}" >&2
      exit 1
      ;;
  esac
else
  log "✓ No .snap/tickets/ cache to drop."
fi

# --- 6. Bump snap.config.json.version → 1.2 ------------------------------
if [ -f "$NEW_CFG" ]; then
  CUR_VER=$(jq -r '.version // ""' "$NEW_CFG")
  if [ "$CUR_VER" != "1.2" ] && [ "$CUR_VER" != "1.2.0" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      say "→ DRY: bump snap.config.json.version ${CUR_VER:-<absent>} → 1.2"
    else
      tmp=$(mktemp)
      jq '.version = "1.2"' "$NEW_CFG" > "$tmp" && mv "$tmp" "$NEW_CFG"
      say "→ ✓ snap.config.json.version = 1.2"
    fi
  else
    log "✓ snap.config.json.version already ${CUR_VER}"
  fi
fi

say ""
say "✅ Migration v1.1.0 → v1.2.0 OK"
say "   Renames        : snapship.config.json, .env.snapship, .snap/features/"
say "   Meta migrate   : feature_id → story_id, epic_link dropped"
say "   Tickets cache  : ${DEC_DROP_TICKETS}"
say ""
say "   Next manual steps :"
say "   - Edit .snap/stories/<id>/meta.json: set parent_epic_id if Epic-linked"
say "   - Add target_version (semver) per meta if applicable"
say "   - Run /snap:fetch --probe-tracker to validate tracker connectivity"
