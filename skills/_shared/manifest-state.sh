#!/usr/bin/env bash
# manifest-state.sh — read / patch feature manifest files under
# `.snap/manifests/`. Centralises the jq plumbing previously inlined in
# step-04-render.md so step files stay declarative and the patch logic is
# testable in isolation.
#
# Subcommands:
#   patch-from-define-state --project-root=PATH --story-id=NN-slug
#     Read `.snap/.define-state.json`, extract feature fields for STORY_ID
#     (priority, domains, impacted_journeys, parent_epic_{id,title,pending}),
#     patch `.snap/manifests/{story_id}.manifest.json` (atomic tmp + mv) and
#     bump `updated_at` to UTC now.
#
# Exit codes:
#   0 — patch applied
#   1 — runtime error (manifest missing, define-state missing, story_id not
#       found in features, jq failure)
#   2 — usage error (missing flag, unknown subcommand)
#
# Notes:
#   - Manifest must exist beforehand (scaffolded by `setup-snap-dir.sh`).
#   - `parent_epic_title` / `parent_epic_pending` are only written when
#     present in the state (avoids overwriting persisted values with empty).
#   - Atomic write : jq → tmp → mv. Race-free against concurrent readers but
#     not against concurrent writers (V3 — see audit Phase 25 for `flock`).

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: manifest-state.sh patch-from-define-state --project-root=PATH --story-id=NN-slug
USAGE
}

cmd_patch_from_define_state() {
  local project_root="" story_id=""
  for arg in "$@"; do
    case "$arg" in
      --project-root=*) project_root="${arg#*=}" ;;
      --story-id=*)     story_id="${arg#*=}" ;;
      -h|--help)        usage; exit 0 ;;
      *) echo "ERROR: unknown flag: $arg" >&2; usage; exit 2 ;;
    esac
  done

  if [ -z "$project_root" ] || [ -z "$story_id" ]; then
    echo "ERROR: --project-root and --story-id are required" >&2
    usage
    exit 2
  fi

  local state_file="${project_root}/.snap/.define-state.json"
  local manifest="${project_root}/.snap/manifests/${story_id}.manifest.json"

  if [ ! -f "$state_file" ]; then
    echo "ERROR: define-state not found: $state_file" >&2
    exit 1
  fi
  if [ ! -f "$manifest" ]; then
    echo "ERROR: manifest not found: $manifest" >&2
    exit 1
  fi

  # Verify the story_id exists in features[] before extracting — surfaces a
  # clear error instead of jq-empty downstream.
  local found
  found=$(jq -r --arg fid "$story_id" \
    '.features // [] | map(select(.story_id == $fid)) | length' \
    "$state_file")
  if [ "$found" != "1" ]; then
    echo "ERROR: story_id '$story_id' not found in $state_file (matches: $found)" >&2
    exit 1
  fi

  local domains_json journeys_json priority
  local parent_epic_id parent_epic_title parent_epic_pending
  domains_json=$(jq -c --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid) | (.domains // [])' \
    "$state_file")
  journeys_json=$(jq -c --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid)
     | (.impacted_journeys // [])
     | map({domain: .domain, journey_slug: .journey_slug})' \
    "$state_file")
  priority=$(jq -r --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid) | (.priority // "")' \
    "$state_file")
  parent_epic_id=$(jq -r --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid) | (.parent_epic_id // "")' \
    "$state_file")
  parent_epic_title=$(jq -r --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid) | (.parent_epic_title // "")' \
    "$state_file")
  parent_epic_pending=$(jq -r --arg fid "$story_id" \
    '.features[] | select(.story_id == $fid) | (.parent_epic_pending // false)' \
    "$state_file")

  local now tmp
  now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  tmp=$(mktemp)

  if ! jq \
       --arg prio "$priority" \
       --argjson domains "$domains_json" \
       --argjson journeys "$journeys_json" \
       --arg pepic "$parent_epic_id" \
       --arg petitle "$parent_epic_title" \
       --argjson ppending "$parent_epic_pending" \
       --arg ts "$now" '
    (if $prio != "" then .priority = $prio else . end)
    | .domains = $domains
    | .impacted_journeys = $journeys
    | (if $pepic != "" then .parent_epic_id = $pepic else . end)
    | (if $petitle != "" then .parent_epic_title = $petitle else . end)
    | (if $ppending == true then .parent_epic_pending = true else . end)
    | .updated_at = $ts
  ' "$manifest" > "$tmp"; then
    trash "$tmp" 2>/dev/null || true
    echo "ERROR: jq patch failed for $manifest" >&2
    exit 1
  fi

  mv "$tmp" "$manifest"
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  patch-from-define-state) shift; cmd_patch_from_define_state "$@" ;;
  -h|--help) usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
