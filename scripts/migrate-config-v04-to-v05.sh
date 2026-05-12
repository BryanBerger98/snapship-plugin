#!/usr/bin/env bash
# migrate-config-v04-to-v05.sh — One-shot migration: snapship.config.json v0.4 → v0.5.
#
# Breaking changes v0.5:
#   - wireframes.frame0_api_port      → wireframes.frame0.api_port
#   - wireframes.penpot_export_dir    → wireframes.penpot.export_dir
#   - wireframes.penpot_file_id       → wireframes.penpot.file_id
#   - wireframes.penpot_file_name     → wireframes.penpot.file_name
#
# Non-bundled tool. Run once per project root after upgrading snap to v0.5.
#
# Usage:
#   migrate-config-v04-to-v05.sh [--dry-run] [--project-root=PATH] [--file=PATH]
#
# Exit codes:
#   0 = ok (or dry-run with diff printed)
#   1 = bad args / file missing / jq error
#   2 = file already in v0.5 shape (nothing to migrate) — non-error idempotent exit

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
CONFIG_FILE=""
DRY_RUN="false"

usage() {
  cat <<EOF
Usage: migrate-config-v04-to-v05.sh [OPTIONS]

Migre snapship.config.json depuis clés plates v0.4 vers blocs nestés v0.5.

Options:
  --project-root=PATH  Racine projet (défaut: \$PWD ou \$SNAP_PROJECT_ROOT)
  --file=PATH          Chemin explicite vers le fichier config (sinon: <root>/snapship.config.json)
  --dry-run            N'écrit rien, affiche le résultat sur stdout
  -h, --help           Aide

Migrations appliquées:
  wireframes.frame0_api_port      → wireframes.frame0.api_port
  wireframes.penpot_export_dir    → wireframes.penpot.export_dir
  wireframes.penpot_file_id       → wireframes.penpot.file_id
  wireframes.penpot_file_name     → wireframes.penpot.file_name

Backup: fichier original sauvegardé en <file>.bak avant écriture (sauf dry-run).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --file=*)         CONFIG_FILE="${1#--file=}" ;;
    --dry-run)        DRY_RUN="true" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$CONFIG_FILE" ] && CONFIG_FILE="${PROJECT_ROOT}/snapship.config.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config file not found: $CONFIG_FILE" >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

if ! jq empty "$CONFIG_FILE" 2>/dev/null; then
  echo "ERROR: invalid JSON in $CONFIG_FILE" >&2
  exit 1
fi

# Detect: any flat key present?
HAS_FLAT=$(jq '
  (.wireframes // {}) as $w
  | ($w | has("frame0_api_port")
      or has("penpot_export_dir")
      or has("penpot_file_id")
      or has("penpot_file_name"))
' "$CONFIG_FILE")

if [ "$HAS_FLAT" != "true" ]; then
  echo "INFO: $CONFIG_FILE déjà en forme v0.5 (aucune clé plate détectée), rien à migrer." >&2
  exit 2
fi

MIGRATED=$(jq '
  if (.wireframes // null) == null then . else
    .wireframes |= (
      . as $w
      | (.frame0 // {}) as $f0
      | (.penpot // {}) as $pp
      | (if $w | has("frame0_api_port") then
          .frame0 = ($f0 + {api_port: $w.frame0_api_port})
        else . end)
      | (if $w | has("penpot_export_dir") then
          .penpot = ($pp + {export_dir: $w.penpot_export_dir})
        else . end)
      | (if $w | has("penpot_file_id") then
          .penpot = ((.penpot // $pp) + {file_id: $w.penpot_file_id})
        else . end)
      | (if $w | has("penpot_file_name") then
          .penpot = ((.penpot // $pp) + {file_name: $w.penpot_file_name})
        else . end)
      | del(.frame0_api_port, .penpot_export_dir, .penpot_file_id, .penpot_file_name)
    )
  end
' "$CONFIG_FILE")

if [ "$DRY_RUN" = "true" ]; then
  printf '%s\n' "$MIGRATED"
  exit 0
fi

cp "$CONFIG_FILE" "${CONFIG_FILE}.bak"
printf '%s\n' "$MIGRATED" > "$CONFIG_FILE"
echo "OK: migré $CONFIG_FILE (backup: ${CONFIG_FILE}.bak)" >&2
exit 0
