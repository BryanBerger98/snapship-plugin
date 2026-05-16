#!/usr/bin/env bash
# detect-repo-templates.sh — Detect repo-native issue/PR templates.
#
# Scans the project for host-native templates (GitHub / GitLab conventions)
# and echoes the matching template path on stdout. Echoes nothing (exit 0)
# when no repo-native template matches — the caller falls back to bundled.
#
# Markdown templates only. YAML issue forms (.yml/.yaml) are ignored — the
# plugin renders markdown scaffolds, it does not parse issue-form schemas.
#
# Output: absolute path to a repo-native template on stdout, or empty.
# Exit codes:
#   0 = success (path found, or none found — check for empty output)
#   1 = invalid args / unknown kind / missing required arg
#
# Usage:
#   detect-repo-templates.sh --kind=ticket --type=bug --platform=github
#   detect-repo-templates.sh --kind=pr --platform=gitlab
#
# Conventions scanned:
#   ticket/github → .github/ISSUE_TEMPLATE/*.md, legacy .github/ISSUE_TEMPLATE.md
#   ticket/gitlab → .gitlab/issue_templates/*.md
#   ticket/jira   → (none — Jira has no repo-native template convention)
#   pr/github     → .github/PULL_REQUEST_TEMPLATE.md (+ root, docs/, dir form)
#   pr/gitlab     → .gitlab/merge_request_templates/*.md

set -euo pipefail

KIND=""
TYPE=""
PLATFORM=""
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

usage() {
  cat <<'EOF'
Usage: detect-repo-templates.sh --kind=KIND [--type=TYPE] --platform=PLATFORM [--project-root=PATH]

Detect a repo-native (.github/.gitlab) template. Echoes the path on stdout,
or nothing when no repo-native template matches.

Options:
  --kind=KIND          One of: ticket | pr
  --type=TYPE          Required when kind=ticket. One of: user-story | bug | epic | task
  --platform=PLATFORM  ticket: github|gitlab|jira ; pr: github|gitlab
  --project-root=PATH  Project root (default: $PWD or $SNAP_PROJECT_ROOT)
  -h, --help           Show this help
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
[ -d "$PROJECT_ROOT" ] || { echo "ERROR: project root not a directory: $PROJECT_ROOT" >&2; exit 1; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

case "$KIND" in
  ticket)
    [ -n "$TYPE" ]     || { echo "ERROR: --type required for kind=ticket" >&2; exit 1; }
    [ -n "$PLATFORM" ] || { echo "ERROR: --platform required for kind=ticket" >&2; exit 1; }
    case "$TYPE" in
      user-story|bug|epic|task) ;;
      *) echo "ERROR: invalid --type='$TYPE' (user-story|bug|epic|task)" >&2; exit 1 ;;
    esac
    case "$PLATFORM" in
      github|gitlab|jira) ;;
      *) echo "ERROR: invalid --platform='$PLATFORM' for kind=ticket" >&2; exit 1 ;;
    esac
    ;;
  pr)
    [ -n "$PLATFORM" ] || { echo "ERROR: --platform required for kind=pr" >&2; exit 1; }
    case "$PLATFORM" in
      github|gitlab) ;;
      *) echo "ERROR: invalid --platform='$PLATFORM' for kind=pr (github|gitlab)" >&2; exit 1 ;;
    esac
    ;;
  *)
    echo "ERROR: invalid --kind='$KIND' (ticket|pr)" >&2
    exit 1
    ;;
esac

to_lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

# Map a template filename (basename, no extension) to a ticket type, or empty.
filename_to_type() {
  case "$(to_lower "$1")" in
    *bug*|*defect*)    echo "bug" ;;
    *epic*)            echo "epic" ;;
    *task*|*chore*)    echo "task" ;;
    *story*|*feature*) echo "user-story" ;;
    *)                 echo "" ;;
  esac
}

# Echo the first *.md file in dir $1 whose filename maps to type $2.
find_typed_template() {
  local dir="$1" want="$2" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(filename_to_type "$(basename "$f" .md)")" = "$want" ] || continue
    printf '%s\n' "$f"
    return 0
  done
  return 0
}

# Echo the first existing file among the arguments.
first_existing() {
  local f
  for f in "$@"; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 0
}

# Echo a *.md file from dir $1: prefer one named "default", else the first.
pick_pr_dir() {
  local dir="$1" f
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.md; do
    [ -f "$f" ] || continue
    [ "$(to_lower "$(basename "$f")")" = "default.md" ] && { printf '%s\n' "$f"; return 0; }
  done
  for f in "$dir"/*.md; do
    [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
  done
  return 0
}

R="$PROJECT_ROOT"
RESULT=""

case "$KIND" in
  ticket)
    case "$PLATFORM" in
      github)
        RESULT=$(find_typed_template "$R/.github/ISSUE_TEMPLATE" "$TYPE")
        [ -n "$RESULT" ] || RESULT=$(find_typed_template "$R/.github/issue_template" "$TYPE")
        # Legacy single-file template — applies to any issue type.
        [ -n "$RESULT" ] || RESULT=$(first_existing \
          "$R/.github/ISSUE_TEMPLATE.md" \
          "$R/.github/issue_template.md" \
          "$R/ISSUE_TEMPLATE.md" \
          "$R/docs/ISSUE_TEMPLATE.md")
        ;;
      gitlab)
        RESULT=$(find_typed_template "$R/.gitlab/issue_templates" "$TYPE")
        ;;
      jira)
        # No repo-native template convention for Jira.
        RESULT=""
        ;;
    esac
    ;;
  pr)
    case "$PLATFORM" in
      github)
        RESULT=$(first_existing \
          "$R/.github/PULL_REQUEST_TEMPLATE.md" \
          "$R/.github/pull_request_template.md" \
          "$R/PULL_REQUEST_TEMPLATE.md" \
          "$R/pull_request_template.md" \
          "$R/docs/PULL_REQUEST_TEMPLATE.md" \
          "$R/docs/pull_request_template.md")
        [ -n "$RESULT" ] || RESULT=$(pick_pr_dir "$R/.github/PULL_REQUEST_TEMPLATE")
        ;;
      gitlab)
        RESULT=$(pick_pr_dir "$R/.gitlab/merge_request_templates")
        ;;
    esac
    ;;
esac

[ -n "$RESULT" ] && printf '%s\n' "$RESULT"
exit 0
