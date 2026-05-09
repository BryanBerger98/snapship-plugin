#!/usr/bin/env bash
# session-start-hook.sh — artysan opt-in pre-load
#
# Installed at .claude/hooks/session-start.sh on user opt-in. Claude Code
# runs this script when a new session starts and injects its stdout into
# the model's initial context window via the SessionStart hook channel.
#
# Goal: pre-load a compact, high-signal summary of the project's artysan
# state so the model does not waste turns reading the same files.
#
# What this emits (in order, each block bounded by markers):
#   1. artysan.config.json (if present)        — testing.* commands, naming
#   2. PRD global summary                      — vision + feature index
#   3. Active feature progress                 — current step, last status
#   4. Open tickets                            — top N by priority
#   5. Recent telemetry                        — last N skill runs
#
# Variables (substituted at install time):
#   {{project_root}}            absolute path of the project (defaults to $PWD)
#   {{max_tickets}}             max open tickets to show (default 10)
#   {{max_telemetry}}           max telemetry lines to show (default 20)
#   {{include_progress}}        true|false — include progress.md
#   {{include_telemetry}}       true|false — include telemetry tail

set -euo pipefail

PROJECT_ROOT="{{project_root}}"
MAX_TICKETS="{{max_tickets}}"
MAX_TELEMETRY="{{max_telemetry}}"
INCLUDE_PROGRESS="{{include_progress}}"
INCLUDE_TELEMETRY="{{include_telemetry}}"

[ -d "$PROJECT_ROOT" ] || { echo "[artysan-hook] PROJECT_ROOT not found: $PROJECT_ROOT" >&2; exit 0; }
cd "$PROJECT_ROOT"

ART_DIR=".claude/product"

block() {
  local title="$1"
  echo ""
  echo "═══ ${title} ═══"
}

emit_config() {
  local f="artysan.config.json"
  [ -f "$f" ] || return 0
  block "artysan.config.json"
  jq '{
    version: .version,
    naming: .naming,
    testing: .testing,
    platforms: .platforms
  }' "$f" 2>/dev/null || cat "$f"
}

emit_prd_global() {
  local f="${ART_DIR}/prd-global.md"
  [ -f "$f" ] || return 0
  block "PRD global (head)"
  head -n 60 "$f"
}

emit_active_feature() {
  local active_file="${ART_DIR}/.active-feature"
  [ -f "$active_file" ] || return 0
  local fid
  fid=$(cat "$active_file")
  block "Active feature: ${fid}"

  local prd="${ART_DIR}/features/${fid}/prd-feature.md"
  [ -f "$prd" ] && head -n 40 "$prd"

  if [ "$INCLUDE_PROGRESS" = "true" ]; then
    local prog="${ART_DIR}/features/${fid}/progress.md"
    if [ -f "$prog" ]; then
      block "Progress (last 10 entries)"
      tail -n 10 "$prog"
    fi
  fi
}

emit_open_tickets() {
  local index="${ART_DIR}/tickets-index.ndjson"
  [ -f "$index" ] || return 0
  block "Open tickets (top ${MAX_TICKETS})"
  jq -r 'select(.state == "open") | "\(.ref)\t\(.priority // "-")\t\(.title)"' "$index" 2>/dev/null \
    | sort -k2 \
    | head -n "$MAX_TICKETS" \
    || true
}

emit_telemetry() {
  [ "$INCLUDE_TELEMETRY" = "true" ] || return 0
  local f="${ART_DIR}/telemetry.ndjson"
  [ -f "$f" ] || return 0
  block "Telemetry (last ${MAX_TELEMETRY} events)"
  tail -n "$MAX_TELEMETRY" "$f"
}

echo "═══ artysan SessionStart pre-load ═══"
echo "project_root: $(pwd)"
echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_config
emit_prd_global
emit_active_feature
emit_open_tickets
emit_telemetry

echo ""
echo "═══ end pre-load ═══"
