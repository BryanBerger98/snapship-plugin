#!/usr/bin/env bash
# resolve-template.sh — Resolve a template: config override > repo-native > bundled.
#
# Resolution order:
#   1. Config override — templates.<key> in snap.config.json. Resolved
#      against project root; mustache-rendered (render-template.sh).
#   2. Repo-native — host template under .github/.gitlab (ticket/pr only).
#      Gated by templates.use_repo_native (default true). Filled as a scaffold
#      (Claude fills the sections), not mustache-rendered.
#   3. Bundled — default template under skills/_shared/templates/. Mustache.
#
# Output: a JSON object on stdout:
#   {"path":"<abs>","source":"config|repo-native|bundled","render_mode":"mustache|scaffold"}
#
# Exit codes:
#   0 = success
#   1 = invalid args / unknown kind / missing required arg
#   2 = template file not found (config override or bundled)
#
# Usage:
#   resolve-template.sh --kind=ticket --type=user-story --platform=github
#   resolve-template.sh --kind=pr --platform=github
#   resolve-template.sh --kind=review-thread --platform=jira
#   resolve-template.sh --kind=aggregated-feedback
#
# Layout (bundled defaults):
#   tickets/{user-story,bug,epic}/{github,gitlab,jira}.md
#   pr/{github,gitlab,default}.md
#   review-thread/{github,gitlab,jira}.md
#   aggregated-feedback.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
KIND=""
TYPE=""
PLATFORM=""

usage() {
  cat <<'EOF'
Usage: resolve-template.sh --kind=KIND [--type=TYPE] [--platform=PLATFORM] [--project-root=PATH]

Resolve a template (config override > repo-native > bundled).

Options:
  --kind=KIND               One of: ticket | pr | review-thread | aggregated-feedback
  --type=TYPE               Required when kind=ticket. One of: user-story | bug | epic
  --platform=PLATFORM       Required when kind in {ticket, pr, review-thread}.
                            ticket: github|gitlab|jira
                            pr: github|gitlab (falls back to default if absent)
                            review-thread: github|gitlab|jira
  --project-root=PATH       Project root (default: $PWD or $SNAP_PROJECT_ROOT)
  -h, --help                Show this help

Resolution:
  1. Config override — templates.<key> from resolved config. Mustache.
  2. Repo-native — .github/.gitlab host template (ticket/pr only). Scaffold.
  3. Bundled — default under skills/_shared/templates/. Mustache.

Output (JSON on stdout):
  {"path":"...","source":"config|repo-native|bundled","render_mode":"mustache|scaffold"}

Config keys per kind:
  ticket           → templates.tickets.<type>     (user_story|bug|epic)
  pr               → templates.pr
  review-thread    → templates.review_thread
  aggregated-feedback → templates.aggregated_feedback
  (repo-native layer gated by templates.use_repo_native, default true)
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --kind=*)         KIND="${1#--kind=}" ;;
    --type=*)         TYPE="${1#--type=}" ;;
    --platform=*)     PLATFORM="${1#--platform=}" ;;
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -n "$KIND" ] || { echo "ERROR: --kind required" >&2; exit 1; }

case "$KIND" in
  ticket)
    [ -n "$TYPE" ]     || { echo "ERROR: --type required for kind=ticket" >&2; exit 1; }
    [ -n "$PLATFORM" ] || { echo "ERROR: --platform required for kind=ticket" >&2; exit 1; }
    case "$TYPE" in
      user-story|bug|epic) ;;
      *) echo "ERROR: invalid --type='$TYPE' (expected: user-story|bug|epic)" >&2; exit 1 ;;
    esac
    case "$PLATFORM" in
      github|gitlab|jira) ;;
      *) echo "ERROR: invalid --platform='$PLATFORM' for kind=ticket" >&2; exit 1 ;;
    esac
    ;;
  pr)
    [ -n "$PLATFORM" ] || { echo "ERROR: --platform required for kind=pr" >&2; exit 1; }
    case "$PLATFORM" in
      github|gitlab|default) ;;
      *) echo "ERROR: invalid --platform='$PLATFORM' for kind=pr (github|gitlab|default)" >&2; exit 1 ;;
    esac
    ;;
  review-thread)
    [ -n "$PLATFORM" ] || { echo "ERROR: --platform required for kind=review-thread" >&2; exit 1; }
    case "$PLATFORM" in
      github|gitlab|jira) ;;
      *) echo "ERROR: invalid --platform='$PLATFORM' for kind=review-thread" >&2; exit 1 ;;
    esac
    ;;
  aggregated-feedback)
    ;;
  *)
    echo "ERROR: invalid --kind='$KIND' (ticket|pr|review-thread|aggregated-feedback)" >&2
    exit 1
    ;;
esac

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

TYPE_KEY="${TYPE//-/_}"

CONFIG_JSON=$(SNAP_PROJECT_ROOT="$PROJECT_ROOT" bash "${SCRIPT_DIR}/load-config.sh" --no-validate 2>/dev/null || echo '{}')

case "$KIND" in
  ticket)              JQ_PATH=".templates.tickets.${TYPE_KEY}" ;;
  pr)                  JQ_PATH=".templates.pr" ;;
  review-thread)       JQ_PATH=".templates.review_thread" ;;
  aggregated-feedback) JQ_PATH=".templates.aggregated_feedback" ;;
esac

USER_OVERRIDE=$(echo "$CONFIG_JSON" | jq -r "${JQ_PATH} // \"\"")

case "$KIND" in
  ticket)              BUNDLED="${SCRIPT_DIR}/templates/tickets/${TYPE}/${PLATFORM}.md" ;;
  pr)                  BUNDLED="${SCRIPT_DIR}/templates/pr/${PLATFORM}.md" ;;
  review-thread)       BUNDLED="${SCRIPT_DIR}/templates/review-thread/${PLATFORM}.md" ;;
  aggregated-feedback) BUNDLED="${SCRIPT_DIR}/templates/aggregated-feedback.md" ;;
esac

emit() {
  # $1=path  $2=source  $3=render_mode
  jq -nc --arg path "$1" --arg source "$2" --arg mode "$3" \
    '{path:$path, source:$source, render_mode:$mode}'
}

# 1. Config override.
if [ -n "$USER_OVERRIDE" ]; then
  case "$USER_OVERRIDE" in
    /*) RESOLVED="$USER_OVERRIDE" ;;
    *)  RESOLVED="${PROJECT_ROOT}/${USER_OVERRIDE}" ;;
  esac
  if [ ! -f "$RESOLVED" ]; then
    echo "ERROR: template override not found: ${RESOLVED} (config key ${JQ_PATH#.})" >&2
    exit 2
  fi
  emit "$RESOLVED" "config" "mustache"
  exit 0
fi

# 2. Repo-native (.github/.gitlab) — ticket + pr only, gated by config.
# Note: jq's `//` treats false as empty, so test equality explicitly.
USE_REPO_NATIVE=$(echo "$CONFIG_JSON" | jq -r 'if .templates.use_repo_native == false then "false" else "true" end')
if [ "$USE_REPO_NATIVE" = "true" ]; then
  REPO_NATIVE=""
  case "$KIND" in
    ticket)
      REPO_NATIVE=$(bash "${SCRIPT_DIR}/detect-repo-templates.sh" \
        --kind=ticket --type="$TYPE" --platform="$PLATFORM" \
        --project-root="$PROJECT_ROOT")
      ;;
    pr)
      case "$PLATFORM" in
        github|gitlab)
          REPO_NATIVE=$(bash "${SCRIPT_DIR}/detect-repo-templates.sh" \
            --kind=pr --platform="$PLATFORM" \
            --project-root="$PROJECT_ROOT")
          ;;
      esac
      ;;
  esac
  if [ -n "$REPO_NATIVE" ]; then
    emit "$REPO_NATIVE" "repo-native" "scaffold"
    exit 0
  fi
fi

# 3. Bundled default.
if [ ! -f "$BUNDLED" ]; then
  echo "ERROR: bundled template missing: ${BUNDLED}" >&2
  exit 2
fi
emit "$BUNDLED" "bundled" "mustache"
exit 0
