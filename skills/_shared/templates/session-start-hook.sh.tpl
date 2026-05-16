#!/usr/bin/env bash
# session-start-hook.sh — snap opt-in pre-load
#
# Installed at .claude/hooks/session-start.sh on user opt-in. Claude Code
# runs this script when a new session starts and injects its stdout into
# the model's initial context window via the SessionStart hook channel.
#
# Goal: pre-load a compact, high-signal summary of the project's snap
# state so the model does not waste turns reading the same files.
#
# What this emits (in order, each block bounded by markers):
#   1. snap.config.json (if present)       — testing.* commands, naming
#   2. PRD global summary                      — vision + feature index
#   3. Active feature manifest + progress      — current state, last step
#   4. Open tickets                            — top N by priority
#   5. Recent telemetry                        — last N skill runs
#
# Variables (substituted at install time):
#   {{project_root}}            absolute path of the project (defaults to $PWD)
#   {{max_tickets}}             max open tickets to show (default 10)
#   {{max_telemetry}}           max telemetry lines to show (default 20)
#   {{include_progress}}        true|false — include progress.json tail
#   {{include_telemetry}}       true|false — include telemetry tail

set -euo pipefail

PROJECT_ROOT="{{project_root}}"
MAX_TICKETS="{{max_tickets}}"
MAX_TELEMETRY="{{max_telemetry}}"
INCLUDE_PROGRESS="{{include_progress}}"
INCLUDE_TELEMETRY="{{include_telemetry}}"

[ -d "$PROJECT_ROOT" ] || { echo "[snap-hook] PROJECT_ROOT not found: $PROJECT_ROOT" >&2; exit 0; }
cd "$PROJECT_ROOT"

SNAP_DIR=".snap"

block() {
  local title="$1"
  echo ""
  echo "═══ ${title} ═══"
}

emit_config() {
  local f="snap.config.json"
  [ -f "$f" ] || return 0
  block "snap.config.json"
  jq '{
    version: .version,
    naming: .naming,
    testing: .testing,
    repository: .repository,
    tickets: .tickets,
    documentation: .documentation
  }' "$f" 2>/dev/null || cat "$f"
}

emit_prd_global() {
  local f="${SNAP_DIR}/PRDs/_global.md"
  [ -f "$f" ] || return 0
  block "PRD global (head)"
  head -n 60 "$f"
}

emit_active_feature() {
  local active_file="${SNAP_DIR}/.active-feature"
  [ -f "$active_file" ] || return 0
  local fid
  fid=$(cat "$active_file")
  block "Active feature: ${fid}"

  local prd="${SNAP_DIR}/PRDs/${fid}.md"
  [ -f "$prd" ] && head -n 40 "$prd"

  local manifest="${SNAP_DIR}/manifests/${fid}.manifest.json"
  if [ -f "$manifest" ]; then
    block "Manifest"
    jq '{state, refs, tickets_count, lang}' "$manifest" 2>/dev/null || cat "$manifest"
  fi

  if [ "$INCLUDE_PROGRESS" = "true" ]; then
    local prog="${SNAP_DIR}/progress.json"
    if [ -f "$prog" ]; then
      block "Progress (in-flight for ${fid})"
      jq --arg fid "$fid" '.in_flight | map(select(.story_id == $fid))' "$prog" 2>/dev/null || true
    fi
  fi
}

emit_open_tickets() {
  local active_file="${SNAP_DIR}/.active-feature"
  [ -f "$active_file" ] || return 0
  local fid
  fid=$(cat "$active_file")
  local tickets="${SNAP_DIR}/tickets/${fid}.json"
  [ -f "$tickets" ] || return 0
  block "Open tickets (top ${MAX_TICKETS}) — ${fid}"
  jq -r --argjson n "$MAX_TICKETS" '
    .tickets
    | map(select(.status != "done" and .status != "shipped"))
    | sort_by(.priority // "z")
    | .[0:$n]
    | .[] | "\(.local_id)\t\(.status // "-")\t\(.title)"
  ' "$tickets" 2>/dev/null || true
}

emit_telemetry() {
  [ "$INCLUDE_TELEMETRY" = "true" ] || return 0
  local f="skills/_shared/telemetry.log"
  [ -f "$f" ] || return 0
  block "Telemetry (last ${MAX_TELEMETRY} events)"
  tail -n "$MAX_TELEMETRY" "$f"
}

echo "═══ snap SessionStart pre-load ═══"
echo "project_root: $(pwd)"
echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"

emit_config
emit_prd_global
emit_active_feature
emit_open_tickets
emit_telemetry

echo ""
echo "═══ end pre-load ═══"
