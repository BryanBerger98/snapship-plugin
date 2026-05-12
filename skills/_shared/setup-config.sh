#!/usr/bin/env bash
# setup-config.sh — initial wizard producing snapship.config.json.
#
# Two modes:
#
#   1. --detect (default)
#      Inspects .git/config + available MCPs + project structure.
#      Emits detected defaults as JSON on stdout. No file is written.
#      Skill consumes this to drive AskUserQuestion prompts.
#
#   2. --write
#      Writes snapship.config.json from explicit field flags +/or merged
#      answer JSON. Refuses to overwrite an existing config unless --force.
#
# Usage:
#   setup-config.sh --detect
#   setup-config.sh --detect --available=affine,frame0
#   setup-config.sh --write --repository-platform=github --tickets-platform=github \
#     --docs-platform=affine --lang=fr
#   setup-config.sh --write --from-answers='{"repository":{"platform":"github"}}'
#   setup-config.sh --write --auto-mode=true   # use detected defaults, fail if any field unresolved

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
MODE=""
FORCE="false"
AUTO_MODE="false"
AVAILABLE_CSV="${SNAP_MCP_AVAILABLE:-}"
FROM_ANSWERS_JSON=""

REPO_PLATFORM=""
REPO_URL=""
TICKETS_PLATFORM=""
DOCS_PLATFORM=""
WIRE_PLATFORM=""
DESIGN_PLATFORM=""
LANG_OVERRIDE=""

usage() {
  cat <<EOF
Usage: setup-config.sh [--detect | --write] [OPTIONS]

Modes:
  --detect          (default) Probe environment, emit detected defaults JSON.
  --write           Materialize snapship.config.json at project root.

Options:
  --project-root=PATH      Project root (default: \$PWD or \$SNAP_PROJECT_ROOT)
  --force                  Overwrite existing snapship.config.json
  --auto-mode=true|false   In --write: skip empty-field check; use detected defaults
  --available=CSV          Override MCP detection (test hook; defaults to \$SNAP_MCP_AVAILABLE)
  --from-answers=JSON      JSON object merged on top of detected defaults
  --repository-platform=github|gitlab
  --repository-url=URL
  --tickets-platform=github|gitlab|jira
  --docs-platform=affine|notion
  --wireframes-platform=frame0|penpot|figma
  --design-platform=penpot|figma  (optionnel — active skill /design)
  --lang=fr|en
  -h, --help               Show this help

Exit codes: 0=ok, 1=bad args / unresolved field, 2=existing config + no --force.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --detect)                    MODE="detect" ;;
    --write)                     MODE="write" ;;
    --project-root=*)            PROJECT_ROOT="${1#--project-root=}" ;;
    --force)                     FORCE="true" ;;
    --auto-mode=*)               AUTO_MODE="${1#--auto-mode=}" ;;
    --available=*)               AVAILABLE_CSV="${1#--available=}" ;;
    --from-answers=*)            FROM_ANSWERS_JSON="${1#--from-answers=}" ;;
    --repository-platform=*)     REPO_PLATFORM="${1#--repository-platform=}" ;;
    --repository-url=*)          REPO_URL="${1#--repository-url=}" ;;
    --tickets-platform=*)        TICKETS_PLATFORM="${1#--tickets-platform=}" ;;
    --docs-platform=*)           DOCS_PLATFORM="${1#--docs-platform=}" ;;
    --wireframes-platform=*)     WIRE_PLATFORM="${1#--wireframes-platform=}" ;;
    --design-platform=*)         DESIGN_PLATFORM="${1#--design-platform=}" ;;
    --lang=*)                    LANG_OVERRIDE="${1#--lang=}" ;;
    -h|--help)                   usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$MODE" ] && MODE="detect"

case "$MODE" in
  detect|write) ;;
  *) echo "ERROR: invalid mode: $MODE" >&2; exit 1 ;;
esac

case "$AUTO_MODE" in true|false) ;; *) echo "ERROR: --auto-mode must be true|false" >&2; exit 1 ;; esac

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }
[ -d "$PROJECT_ROOT" ] || { echo "ERROR: project root missing: $PROJECT_ROOT" >&2; exit 1; }

# --- Detection helpers ----------------------------------------------------

# Parse .git/config to find first remote URL. Echo "" if absent.
detect_git_remote_url() {
  local cfg="$PROJECT_ROOT/.git/config"
  [ -f "$cfg" ] || { echo ""; return 0; }
  awk '
    /^\[remote / { in_remote = 1; next }
    /^\[/        { in_remote = 0; next }
    in_remote && /^[[:space:]]*url[[:space:]]*=/ {
      sub(/^[[:space:]]*url[[:space:]]*=[[:space:]]*/, "")
      print $0
      exit
    }
  ' "$cfg"
}

# Infer "github" or "gitlab" from URL; echo "" if unknown.
infer_repo_platform() {
  local url="$1"
  case "$url" in
    *github.com*) echo "github" ;;
    *gitlab.com*|*gitlab.*) echo "gitlab" ;;
    *) echo "" ;;
  esac
}

# Convert SSH URL to HTTPS (best effort).
ssh_to_https() {
  local url="$1"
  case "$url" in
    git@*:*)
      # git@github.com:owner/repo.git → https://github.com/owner/repo
      local host path
      host="${url#git@}"; host="${host%%:*}"
      path="${url#*:}"; path="${path%.git}"
      echo "https://${host}/${path}"
      ;;
    https://*|http://*)
      echo "${url%.git}"
      ;;
    *) echo "" ;;
  esac
}

# Check MCP availability against AVAILABLE_CSV.
mcp_present() {
  [ -z "$AVAILABLE_CSV" ] && { echo "false"; return 0; }
  local cand
  for cand in "$@"; do
    case ",${AVAILABLE_CSV}," in
      *",${cand},"*) echo "true"; return 0 ;;
    esac
  done
  echo "false"
}

# --- Build detected JSON --------------------------------------------------

raw_remote_url=$(detect_git_remote_url)
detected_repo_platform=$(infer_repo_platform "$raw_remote_url")
detected_repo_http=""
[ -n "$raw_remote_url" ] && detected_repo_http=$(ssh_to_https "$raw_remote_url")

# Tickets default = repo platform (github/gitlab) when known
detected_tickets_platform="$detected_repo_platform"

# Docs: prefer affine if MCP present, else notion if present, else "" (must ask)
detected_docs_platform=""
if [ "$(mcp_present affine)" = "true" ]; then
  detected_docs_platform="affine"
elif [ "$(mcp_present notion)" = "true" ]; then
  detected_docs_platform="notion"
fi

# Wireframes: frame0 (only supported value)
detected_wire_platform="frame0"

DETECTED=$(jq -nc \
  --arg repo_platform "$detected_repo_platform" \
  --arg repo_http     "$detected_repo_http" \
  --arg repo_ssh      "$raw_remote_url" \
  --arg tickets       "$detected_tickets_platform" \
  --arg docs          "$detected_docs_platform" \
  --arg wire          "$detected_wire_platform" \
  --arg lang          "fr" '
  {
    repository: (
      {}
      | if $repo_platform != "" then .platform = $repo_platform else . end
      | if $repo_http     != "" then .http_url = $repo_http     else . end
      | if ($repo_ssh != "" and ($repo_ssh | startswith("git@"))) then .ssh_url = $repo_ssh else . end
    ),
    tickets:       (if $tickets != "" then {platform: $tickets} else {} end),
    documentation: (if $docs    != "" then {platform: $docs}    else {} end),
    wireframes:    {platform: $wire},
    defaults:      {lang: $lang}
  }
')

# --- Detect mode: emit and exit -------------------------------------------
if [ "$MODE" = "detect" ]; then
  echo "$DETECTED"
  exit 0
fi

# --- Write mode -----------------------------------------------------------

OUTPUT="$PROJECT_ROOT/snapship.config.json"

if [ -e "$OUTPUT" ] && [ "$FORCE" != "true" ]; then
  echo "ERROR: $OUTPUT exists; pass --force to overwrite" >&2
  exit 2
fi

# Build override JSON from explicit flags
OVERRIDES=$(jq -nc \
  --arg rp "$REPO_PLATFORM" \
  --arg ru "$REPO_URL" \
  --arg tp "$TICKETS_PLATFORM" \
  --arg dp "$DOCS_PLATFORM" \
  --arg wp "$WIRE_PLATFORM" \
  --arg dsp "$DESIGN_PLATFORM" \
  --arg lg "$LANG_OVERRIDE" '
  {}
  | if $rp != "" then .repository      = (.repository // {}      | .platform = $rp) else . end
  | if $ru != "" then .repository      = (.repository // {}      | .http_url = $ru) else . end
  | if $tp != "" then .tickets         = (.tickets // {}         | .platform = $tp) else . end
  | if $dp != "" then .documentation   = (.documentation // {}   | .platform = $dp) else . end
  | if $wp != "" then .wireframes      = (.wireframes // {}      | .platform = $wp) else . end
  | if $dsp != "" then .design         = (.design // {}          | .platform = $dsp) else . end
  | if $lg != "" then .defaults        = (.defaults // {}        | .lang     = $lg) else . end
')

ANSWERS_JSON='{}'
if [ -n "$FROM_ANSWERS_JSON" ]; then
  if ! echo "$FROM_ANSWERS_JSON" | jq empty 2>/dev/null; then
    echo "ERROR: --from-answers must be valid JSON" >&2
    exit 1
  fi
  ANSWERS_JSON="$FROM_ANSWERS_JSON"
fi

# Deep-merge: detected (base) ← answers ← overrides
MERGED=$(jq -n \
  --argjson base "$DETECTED" \
  --argjson answers "$ANSWERS_JSON" \
  --argjson overrides "$OVERRIDES" '
  def deepmerge(a; b):
    if (a | type) == "object" and (b | type) == "object" then
      reduce (a + b | keys_unsorted | unique[]) as $k
        ({}; .[$k] = (
          if (a[$k] | type) == "object" and (b[$k] | type) == "object"
          then deepmerge(a[$k]; b[$k])
          else (b[$k] // a[$k])
          end
        ))
    else b // a end;
  deepmerge(deepmerge($base; $answers); $overrides)
')

# Add version + $schema (github raw URL — portable across install locations,
# resolvable by IDEs once plugin published; relative paths break since the plugin
# lives in CC cache dir, not in the user's project root)
FINAL=$(echo "$MERGED" | jq '. + {version: "1.0"} | {"$schema": "https://raw.githubusercontent.com/BryanBerger98/snapship-plugin/main/skills/_shared/schemas/config.schema.json"} + .')

# In auto-mode=true, ensure every required field resolved
required_check_msg=""
check_field() {
  local path="$1" label="$2"
  local v
  v=$(echo "$FINAL" | jq -r "$path // \"\"")
  if [ -z "$v" ]; then
    required_check_msg="${required_check_msg}\n  - ${label} (${path})"
  fi
}

if [ "$AUTO_MODE" = "true" ]; then
  check_field ".repository.platform"    "repository.platform"
  check_field ".tickets.platform"       "tickets.platform"
  check_field ".documentation.platform" "documentation.platform"
  if [ -n "$required_check_msg" ]; then
    echo "ERROR: --auto-mode=true but required fields unresolved:" >&2
    printf '%b\n' "$required_check_msg" >&2
    exit 1
  fi
fi

echo "$FINAL" | jq '.' > "$OUTPUT"

# Echo path written (machine-readable single line)
printf '%s\n' "$OUTPUT"
exit 0
