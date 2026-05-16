#!/usr/bin/env bash
# load-config.sh — Read snap.config.json, merge defaults, validate schema, resolve inheritance.
# Output: normalized JSON config on stdout (no file cache — capture in bash var).
# Exit codes:
#   0 = success
#   1 = invalid JSON / failed schema validation / unresolved inheritance
#   2 = unsupported config version
#
# Usage: load-config.sh [--project-root=PATH] [--no-validate]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
NO_VALIDATE=false

usage() {
  cat <<EOF
Usage: load-config.sh [OPTIONS]

Reads snap.config.json (project root), merges bundled defaults, validates
schema, resolves inheritance, outputs normalized JSON to stdout.

Options:
  --project-root=PATH  Project root (default: \$PWD or \$SNAP_PROJECT_ROOT)
  --no-validate        Skip JSON Schema validation
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --no-validate)    NO_VALIDATE=true ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

CONFIG_FILE="${PROJECT_ROOT}/snap.config.json"
SCHEMA_FILE="${SCRIPT_DIR}/schemas/config.schema.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

# --- Bundled defaults ---
DEFAULTS=$(cat <<'JSON'
{
  "version": "1.0",
  "naming": {
    "story_slug_max_length": 40,
    "branch_pattern": "{type}/{ticket_id}",
    "commit_pattern": "{commit_type}({scope}): {message}"
  },
  "ai": {
    "max_parallel_agents": 5,
    "mcp_servers_required": [],
    "mcp_servers_optional": []
  },
  "develop": {
    "review_cycles_max": 3,
    "auto_apply_review_feedback": true,
    "fail_strategy": "next-ticket",
    "reviews": {
      "technical": { "severity_threshold": "minor" },
      "functional": { "severity_threshold": "minor" },
      "security":   { "severity_threshold": "info" }
    }
  },
  "qa": {
    "qa_cycles_max": 2,
    "auto_apply_qa_feedback": true,
    "severity_threshold": "minor",
    "retrigger_review": false,
    "regression": { "enabled": true, "scope": "impacted" },
    "wireframe_check": {
      "enabled": false,
      "mode": "playwright",
      "diff_threshold_pct": 5,
      "severity_on_mismatch": "major"
    }
  },
  "wireframes": {
    "platform": "frame0",
    "export_format": "png",
    "export_scale": 2,
    "naming_pattern": "{story_id}-{screen_name}",
    "frame0": { "api_port": 58320 }
  },
  "lifecycle_scripts": {},
  "templates": {
    "use_repo_native": true,
    "tickets": {
      "user_story": null,
      "bug": null,
      "epic": null
    },
    "pr": null,
    "review_thread": null,
    "aggregated_feedback": null
  },
  "defaults": {
    "lang": "fr",
    "auto_mode": false,
    "save_mode": true,
    "branch_mode": true,
    "economy_mode": false,
    "worktree": {
      "path": "./.worktrees",
      "default_root": "{branch_name}",
      "destroy": "after_merge"
    }
  }
}
JSON
)

# --- Read user config (or empty if absent) ---
if [ -f "$CONFIG_FILE" ]; then
  if ! USER_CONFIG=$(jq '.' "$CONFIG_FILE" 2>&1); then
    echo "ERROR: ${CONFIG_FILE} is not valid JSON:" >&2
    echo "$USER_CONFIG" >&2
    exit 1
  fi
else
  USER_CONFIG='{}'
fi

# --- Schema validation (raw user config) ---
if [ "$NO_VALIDATE" = false ] && [ -f "$CONFIG_FILE" ]; then
  if command -v ajv >/dev/null 2>&1; then
    AJV="ajv"
  elif command -v npx >/dev/null 2>&1; then
    AJV="npx -y ajv-cli"
  else
    echo "WARN: ajv-cli unavailable, skipping schema validation" >&2
    NO_VALIDATE=true
  fi
fi

if [ "$NO_VALIDATE" = false ] && [ -f "$CONFIG_FILE" ]; then
  if ! validation=$($AJV validate --spec=draft2020 -s "$SCHEMA_FILE" -d "$CONFIG_FILE" --strict=false 2>&1); then
    echo "ERROR: ${CONFIG_FILE} fails schema validation:" >&2
    echo "$validation" >&2
    exit 1
  fi
fi

# --- Version compatibility ---
VERSION=$(echo "$USER_CONFIG" | jq -r '.version // "1.0.0"')
case "$VERSION" in
  1.*) ;;
  *)
    echo "ERROR: unsupported config version '${VERSION}'. Run /snap:upgrade." >&2
    exit 2
    ;;
esac

# --- Deep merge: defaults < user (user wins) ---
MERGED=$(jq -n \
  --argjson defaults "$DEFAULTS" \
  --argjson user "$USER_CONFIG" '
  def merge(a; b):
    if (a | type) == "object" and (b | type) == "object" then
      reduce ((a + b) | keys_unsorted[]) as $k (
        {}; .[$k] = merge(a[$k]; b[$k])
      )
    else
      if b == null then a else b end
    end;
  merge($defaults; $user)
')

# --- Resolve inheritance + computed defaults ---
RESOLVED=$(echo "$MERGED" | jq '
  # tickets.platform inherit → repository.platform
    (if (.tickets // null) != null and .tickets.platform == "inherit" then
      if (.repository // null) != null and (.repository.platform // null) != null then
        .tickets.platform = .repository.platform
      else
        .tickets.platform = null
      end
    else . end)
  # naming.ticket_id_regex absent → pattern by platform
  | (if (.naming.ticket_id_regex // null) == null then
      .naming.ticket_id_regex = (
        (.tickets.platform // "jira") as $p
        | if $p == "github" or $p == "gitlab" then "#[0-9]+"
          else "[A-Z]+-[0-9]+" end
      )
    else . end)
  # repository.protected_branches default if repository defined
  | (if (.repository // null) != null and (.repository.protected_branches // null) == null then
      .repository.protected_branches = ["main"]
    else . end)
  # documentation.paths defaults — only when platform != "none"
  | (if (.documentation // null) != null
        and (.documentation.platform // "none") != "none" then
      .documentation.paths = (
        (.documentation.paths // {})
        | (if has("functional_root") | not then .functional_root = "Product Docs" else . end)
        | (if has("prd_root")        | not then .prd_root        = "Change Requests" else . end)
      )
    else . end)
  # documentation.auto_update_mode + auto_update_on_qa_success defaults
  | (if (.documentation // null) != null
        and (.documentation.platform // "none") != "none" then
      (if (.documentation | has("auto_update_mode")) | not then
        .documentation.auto_update_mode = "diff"
      else . end)
      | (if (.documentation | has("auto_update_on_qa_success")) | not then
        .documentation.auto_update_on_qa_success = true
      else . end)
    else . end)
  # wireframes.figma.token_env default
  | (if (.wireframes // null) != null and (.wireframes.figma // null) != null then
      (if (.wireframes.figma | has("token_env")) | not then
        .wireframes.figma.token_env = "FIGMA_ACCESS_TOKEN"
      else . end)
    else . end)
  # design defaults — résolus seulement si bloc design présent (skill opt-in)
  | (if (.design // null) != null then
      (if (.design | has("export_format")) | not then .design.export_format = "png" else . end)
      | (if (.design | has("naming_pattern")) | not then .design.naming_pattern = "{story_id}-{screen_name}-design" else . end)
      | .design.mode_defaults = (
          (.design.mode_defaults // {})
          | (if has("mockup_canvas") | not then .mockup_canvas = "mobile-portrait" else . end)
          | (if has("design_system_source") | not then .design_system_source = "auto" else . end)
        )
      | (if (.design.platform // "") == "penpot" and (.design.penpot // null) != null then
          .design.penpot = (
            .design.penpot
            | (if has("design_system_page") | not then .design_system_page = "Components" else . end)
          )
        else . end)
      | (if (.design.platform // "") == "figma" and (.design.figma // null) != null then
          .design.figma = (
            .design.figma
            | (if has("token_env") | not then .token_env = "FIGMA_ACCESS_TOKEN" else . end)
          )
        else . end)
    else . end)
')

# Inherit unresolved → fail
if echo "$RESOLVED" | jq -e '(.tickets // null) != null and (.tickets.platform // null) == null' >/dev/null; then
  echo "ERROR: tickets.platform=inherit but repository.platform absent" >&2
  exit 1
fi

# --- Warnings (non-blocking) ---
if echo "$RESOLVED" | jq -e '(.tickets // null) != null and .tickets.platform != "jira" and (.tickets.jira // null) != null' >/dev/null; then
  plat=$(echo "$RESOLVED" | jq -r '.tickets.platform')
  echo "WARN: tickets.jira section ignored on platform='${plat}'" >&2
fi

while IFS=$'\t' read -r key path; do
  [ -z "$path" ] && continue
  case "$path" in
    /*) abs="$path" ;;
    *)  abs="${PROJECT_ROOT}/${path}" ;;
  esac
  if [ ! -f "$abs" ]; then
    echo "WARN: lifecycle_scripts.${key} → '${path}' not found" >&2
  fi
done < <(echo "$RESOLVED" | jq -r '(.lifecycle_scripts // {}) | to_entries[] | "\(.key)\t\(.value // "")"')

printf '%s\n' "$RESOLVED"
