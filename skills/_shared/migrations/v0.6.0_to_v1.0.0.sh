#!/usr/bin/env bash
# v0.6.0_to_v1.0.0.sh — Migrate workspace .claude/product/ → .snap/.
#
# Idempotent (re-run safe). Reads:
#   SNAP_PROJECT_ROOT             (required) repo root
#   SNAP_DECISIONS_JSON           (optional) user decisions JSON
#     { "old_workspace": "backup|trash|keep",
#       "republish_prds": "skip|refresh",
#       "tickets_no_tracker": "configure|skip",
#       "daemon_users": "session|manual" }
#   SNAP_DRY_RUN=true             (optional) print actions only, no fs change
#
# Steps :
#   1. Sanity check (.claude/product exists)
#   2. Backup → .snap.bak-v0.6.0-{ts}/ (depend on old_workspace decision)
#   3. Build .snap/ scaffold via setup-snap-dir.sh
#   4. Move each features/{id}/ artifact → typed dir
#   5. Convert meta.json → manifests/{id}.manifest.json (add schema_version)
#   6. Convert domains.json → manifests/_taxonomy.json
#   7. Drop legacy caches (.docs-cache.json, .config-resolved.json, design-gallery.md, .doc-update-cache/, daemon.sh)
#   8. Bump snapship.config.json.version → 1.0.0
#   9. Per old_workspace decision: trash/keep/already-backed-up
#
# Exit 0 = success, 1 = fail.

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
DECISIONS="${SNAP_DECISIONS_JSON:-}"
[ -z "$DECISIONS" ] && DECISIONS='{}'
DRY_RUN="${SNAP_DRY_RUN:-false}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
SCHEMA_VERSION="1.0.0"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }
echo "$DECISIONS" | jq empty 2>/dev/null || { echo "ERROR: SNAP_DECISIONS_JSON invalid" >&2; exit 1; }

OLD_DIR="${PROJECT_ROOT}/.claude/product"
NEW_DIR="${PROJECT_ROOT}/.snap"
NOW=$(date -u +"%Y%m%dT%H%M%SZ")
BACKUP_DIR="${PROJECT_ROOT}/.snap.bak-v0.6.0-${NOW}"

DEC_WORKSPACE=$(echo "$DECISIONS" | jq -r '.old_workspace // "backup"')
DEC_REPUB=$(echo "$DECISIONS" | jq -r '.republish_prds // "skip"')

log()    { printf '  %s\n' "$*"; }
say()    { printf '%s\n' "$*"; }
do_or_say() {
  if [ "$DRY_RUN" = "true" ]; then
    say "DRY: $*"
  else
    # Callers pass a single command string with embedded single-quotes
    # around paths; eval is required to honour those quotes.
    # shellcheck disable=SC2294
    eval "$@"
  fi
}

say "→ Migration v0.6.0 → v1.0.0"
say "  project_root      : ${PROJECT_ROOT}"
say "  old_workspace dec : ${DEC_WORKSPACE}"
say "  dry_run           : ${DRY_RUN}"

# --- 1. Sanity ---
if [ ! -d "$OLD_DIR" ]; then
  if [ -d "$NEW_DIR" ]; then
    say "✓ Déjà migré (.snap/ existe, .claude/product/ absent). Skip."
    exit 0
  fi
  say "✓ Rien à migrer (.claude/product/ absent). Init .snap/ vide."
  do_or_say "bash '${SHARED_DIR}/setup-snap-dir.sh' --project-root='${PROJECT_ROOT}' >/dev/null"
  exit 0
fi

# --- 2. Backup ---
case "$DEC_WORKSPACE" in
  backup)
    say "→ Backup .claude/product/ → ${BACKUP_DIR}"
    do_or_say "cp -R '${OLD_DIR}' '${BACKUP_DIR}'"
    ;;
  trash|keep)
    say "→ Pas de backup (decision=${DEC_WORKSPACE})"
    ;;
  *)
    echo "ERROR: invalid old_workspace decision: ${DEC_WORKSPACE}" >&2
    exit 1
    ;;
esac

# --- 3. Scaffold .snap/ ---
say "→ Scaffold .snap/ via setup-snap-dir.sh"
do_or_say "bash '${SHARED_DIR}/setup-snap-dir.sh' --project-root='${PROJECT_ROOT}' >/dev/null"

# --- 4 + 5. Migrate features/{id}/ + meta.json ---
if [ -d "${OLD_DIR}/features" ]; then
  for FEATURE_DIR in "${OLD_DIR}/features"/*/; do
    [ -d "$FEATURE_DIR" ] || continue
    FID=$(basename "$FEATURE_DIR")
    [[ "$FID" =~ ^[0-9]{2}-[a-z0-9][a-z0-9-]*$ ]] || { say "  ⚠ skip ${FID} (invalid format)"; continue; }
    log "feature ${FID}"

    # meta.json → manifest.json
    OLD_META="${FEATURE_DIR}meta.json"
    NEW_MANIFEST="${NEW_DIR}/manifests/${FID}.manifest.json"
    if [ -f "$OLD_META" ] && [ ! -f "$NEW_MANIFEST" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        log "  DRY: meta.json → manifest.json (+schema_version + refs.prd)"
      else
        jq --arg v "$SCHEMA_VERSION" '
          {schema_version: $v} + .
          | if .prd != null then
              .refs = (.refs // {}) | .refs.prd = (
                (.refs.prd // {})
                + {platform: "notion"}
                + (if .prd.page_id != null then {page_id: .prd.page_id} else {} end)
                + (if .prd.url != null then {url: .prd.url} else {} end)
                + {sync_status: "synced"}
              )
              | del(.prd)
            else . end
        ' "$OLD_META" > "$NEW_MANIFEST"
        log "  ✓ manifest.json"
      fi
    fi

    # prd-feature.md → PRDs/{id}.md (only if not yet synced)
    OLD_PRD="${FEATURE_DIR}prd-feature.md"
    NEW_PRD="${NEW_DIR}/PRDs/${FID}.md"
    if [ -f "$OLD_PRD" ] && [ ! -f "$NEW_PRD" ]; then
      if [ "$DEC_REPUB" = "refresh" ]; then
        do_or_say "cp '${OLD_PRD}' '${NEW_PRD}'"
        log "  ✓ PRDs/${FID}.md (refresh queued)"
      else
        # Drop si déjà synced (refs.prd existe dans nouveau manifest)
        if [ -f "$NEW_MANIFEST" ] && [ "$(jq -r '.refs.prd.page_id // ""' "$NEW_MANIFEST")" != "" ]; then
          log "  - PRDs/${FID}.md dropped (already synced)"
        else
          do_or_say "cp '${OLD_PRD}' '${NEW_PRD}'"
          log "  ✓ PRDs/${FID}.md (local-only, queue push)"
        fi
      fi
    fi

    # tickets.json → tickets/{id}.json
    OLD_TICKETS="${FEATURE_DIR}tickets.json"
    NEW_TICKETS="${NEW_DIR}/tickets/${FID}.json"
    if [ -f "$OLD_TICKETS" ] && [ ! -f "$NEW_TICKETS" ]; then
      do_or_say "cp '${OLD_TICKETS}' '${NEW_TICKETS}'"
      log "  ✓ tickets/${FID}.json"
    fi

    # wireframes/* → wireframes/{id}/*
    if [ -d "${FEATURE_DIR}wireframes" ]; then
      mkdir -p "${NEW_DIR}/wireframes/${FID}"
      do_or_say "cp -R '${FEATURE_DIR}wireframes/.' '${NEW_DIR}/wireframes/${FID}/'"
      log "  ✓ wireframes/${FID}/"
    fi

    # design/* → designs/{id}/*
    if [ -d "${FEATURE_DIR}design" ]; then
      mkdir -p "${NEW_DIR}/designs/${FID}"
      do_or_say "cp -R '${FEATURE_DIR}design/.' '${NEW_DIR}/designs/${FID}/'"
      log "  ✓ designs/${FID}/"
    fi

    # .develop-queue.json → queues/{id}.develop.json
    OLD_QUEUE="${FEATURE_DIR}.develop-queue.json"
    NEW_QUEUE="${NEW_DIR}/queues/${FID}.develop.json"
    if [ -f "$OLD_QUEUE" ] && [ ! -f "$NEW_QUEUE" ]; then
      do_or_say "cp '${OLD_QUEUE}' '${NEW_QUEUE}'"
      log "  ✓ queues/${FID}.develop.json"
    fi

    # progress.md per-feature → dropped (fresh start). Pas migré.
  done
fi

# --- 6. domains.json → _taxonomy.json ---
OLD_DOMAINS="${OLD_DIR}/domains.json"
NEW_TAX="${NEW_DIR}/manifests/_taxonomy.json"
if [ -f "$OLD_DOMAINS" ]; then
  if [ "$DRY_RUN" = "true" ]; then
    say "→ DRY: convert domains.json → _taxonomy.json"
  else
    # Wrap dans nouveau format + ajoute schema_version + workspace placeholder.
    jq -n \
      --arg v "$SCHEMA_VERSION" \
      --slurpfile base "$NEW_TAX" \
      --argjson domains "$(cat "$OLD_DOMAINS")" '
      $base[0]
      | .schema_version = $v
      | .domains = (
          $domains
          | with_entries(
              .value = {
                title: (.value.title // ""),
                page_id: .value.domain_page_id,
                url: (.value.domain_url // ""),
                synced_at: (.value.updated_at // .value.created_at // ""),
                journeys: (.value.journeys // {})
              }
            )
        )
    ' > "${NEW_TAX}.tmp"
    mv "${NEW_TAX}.tmp" "$NEW_TAX"
    say "→ ✓ _taxonomy.json migré (depuis domains.json)"
  fi
fi

# --- 7. Drop legacy caches (rien à faire — old dir backup/trash gère ça) ---
# Mais si decision = keep, on garde tel quel. Si trash, on supprime à l'étape 9.

# --- 8. Bump snapship.config.json.version ---
CFG="${PROJECT_ROOT}/snapship.config.json"
if [ -f "$CFG" ]; then
  CUR_VER=$(jq -r '.version // ""' "$CFG")
  if [ "$CUR_VER" != "1.0" ] && [ "$CUR_VER" != "1.0.0" ]; then
    if [ "$DRY_RUN" = "true" ]; then
      say "→ DRY: bump snapship.config.json.version ${CUR_VER:-<absent>} → 1.0"
    else
      jq '.version = "1.0"' "$CFG" > "${CFG}.tmp"
      mv "${CFG}.tmp" "$CFG"
      say "→ ✓ snapship.config.json.version = 1.0"
    fi
  fi
fi

# --- 9. Old dir cleanup per decision ---
case "$DEC_WORKSPACE" in
  backup|trash)
    if [ "$DRY_RUN" = "true" ]; then
      say "→ DRY: trash ${OLD_DIR}"
    else
      if command -v trash >/dev/null 2>&1; then
        trash "$OLD_DIR"
        say "→ ✓ .claude/product/ trashed (récupérable via corbeille)"
      else
        say "⚠ trash unavailable — ${OLD_DIR} laissé en place. Trash manuellement."
      fi
    fi
    ;;
  keep)
    say "→ .claude/product/ laissé intact (decision=keep)"
    ;;
esac

say ""
say "✅ Migration v0.6.0 → v1.0.0 OK"
[ -d "$BACKUP_DIR" ] && say "   Backup    : ${BACKUP_DIR}"
say "   New root  : ${NEW_DIR}"
say "   Next      : /snap:fetch  # re-sync depuis remote"
