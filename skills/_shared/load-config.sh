#!/usr/bin/env bash
# load-config.sh — Read snapship.config.json, merge defaults, validate schema, resolve inheritance.
# Output: normalized JSON config on stdout.
# Exit codes:
#   0 = success
#   1 = invalid JSON / failed schema validation / unresolved inheritance
#   2 = unsupported config version
#
# Usage: load-config.sh [--project-root=PATH] [--no-cache] [--no-validate]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
USE_CACHE=true
NO_VALIDATE=false

usage() {
  cat <<EOF
Usage: load-config.sh [OPTIONS]

Reads snapship.config.json (project root), merges bundled defaults, validates
schema, resolves inheritance, outputs normalized JSON to stdout.

Options:
  --project-root=PATH  Project root (default: \$PWD or \$SNAP_PROJECT_ROOT)
  --no-cache           Bypass cache (.claude/product/.config-resolved.json)
  --no-validate        Skip JSON Schema validation
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --no-cache)       USE_CACHE=false ;;
    --no-validate)    NO_VALIDATE=true ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

CONFIG_FILE="${PROJECT_ROOT}/snapship.config.json"
CACHE_FILE="${PROJECT_ROOT}/.claude/product/.config-resolved.json"
SCHEMA_FILE="${SCRIPT_DIR}/schemas/config.schema.json"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

mtime() {
  stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
}

# --- Cache fast-path ---
if [ "$USE_CACHE" = true ] && [ -f "$CACHE_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  if [ "$(mtime "$CACHE_FILE")" -ge "$(mtime "$CONFIG_FILE")" ]; then
    cat "$CACHE_FILE"
    exit 0
  fi
fi

# --- Bundled defaults ---
DEFAULTS=$(cat <<'JSON'
{
  "version": "1.0",
  "naming": {
    "feature_slug_max_length": 40,
    "branch_pattern": "{type}/{ticket_id}-{slug}",
    "commit_pattern": "{type}({scope}): {message}"
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
  "lifecycle_scripts": {},
  "templates": {
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
    "economy_mode": false
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
VERSION=$(echo "$USER_CONFIG" | jq -r '.version // "1.0"')
case "$VERSION" in
  1.*) ;;
  *)
    echo "ERROR: unsupported config version '${VERSION}'. Migrate to 1.x." >&2
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
  # documentation.paths defaults (v0.2) — only when platform != "none"
  | (if (.documentation // null) != null
        and (.documentation.platform // "none") != "none" then
      .documentation.paths = (
        (.documentation.paths // {})
        | (if has("functional_root") | not then .functional_root = "Product Docs" else . end)
        | (if has("prd_root")        | not then .prd_root        = "Change Requests" else . end)
      )
    else . end)
  # documentation.auto_update_mode + auto_update_on_qa_success defaults (v0.2)
  # Use has() not // null (// treats false as null → false would get overwritten).
  | (if (.documentation // null) != null
        and (.documentation.platform // "none") != "none" then
      (if (.documentation | has("auto_update_mode")) | not then
        .documentation.auto_update_mode = "diff"
      else . end)
      | (if (.documentation | has("auto_update_on_qa_success")) | not then
        .documentation.auto_update_on_qa_success = true
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

# --- Cache write ---
if [ "$USE_CACHE" = true ] && [ -f "$CONFIG_FILE" ]; then
  mkdir -p "$(dirname "$CACHE_FILE")"
  printf '%s\n' "$RESOLVED" > "$CACHE_FILE"
fi

printf '%s\n' "$RESOLVED"
