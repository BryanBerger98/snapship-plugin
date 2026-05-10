#!/usr/bin/env bash
# detect-codebase.sh — Decide if a directory contains an existing codebase.
#
# Used by /define step-00 to branch greenfield vs extension. Returns a JSON
# object with the verdict and the signals it found, so the skill can show
# the user exactly why the decision was made.
#
# Heuristic (in order, short-circuit on first hit for "yes"):
#   1. Any of these manifests at project root → codebase=true
#      package.json, pyproject.toml, Cargo.toml, go.mod, composer.json,
#      Gemfile, build.gradle, pom.xml, mix.exs, setup.py, deno.json
#   2. .git/ exists AND `git ls-files` returns at least one tracked source
#      file (filtered to common code extensions, ignoring node_modules,
#      vendor, .venv, dist, build) → codebase=true
#   3. Otherwise → codebase=false (greenfield).
#
# Output: JSON on stdout, e.g.
#   {"has_codebase": true, "signals": ["package.json"], "tracked_count": 42}
#   {"has_codebase": false, "signals": [], "tracked_count": 0}
#
# Exit codes: always 0 (this is a probe; downstream code reads the JSON).
#
# Usage: detect-codebase.sh [--project-root=PATH]

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

usage() {
  cat <<EOF
Usage: detect-codebase.sh [--project-root=PATH]

Detect whether the directory contains an existing codebase. Prints a JSON
verdict to stdout with the signals found.

Options:
  --project-root=PATH  Project root (default: \$PWD or \$SNAP_PROJECT_ROOT)
  -h, --help           Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -d "$PROJECT_ROOT" ] || { echo "ERROR: not a directory: $PROJECT_ROOT" >&2; exit 2; }

MANIFESTS=(
  "package.json"
  "pyproject.toml"
  "Cargo.toml"
  "go.mod"
  "composer.json"
  "Gemfile"
  "build.gradle"
  "build.gradle.kts"
  "pom.xml"
  "mix.exs"
  "setup.py"
  "deno.json"
  "deno.jsonc"
)

SOURCE_EXT_REGEX='\.(ts|tsx|js|jsx|mjs|cjs|py|rb|go|rs|java|kt|swift|php|ex|exs|cs|cpp|cc|c|h|hpp|sh|zsh)$'
IGNORE_REGEX='(^|/)(node_modules|vendor|\.venv|venv|dist|build|target|\.next|\.nuxt|coverage|out)(/|$)'

signals=()
tracked_count=0
has_codebase=false

for m in "${MANIFESTS[@]}"; do
  if [ -f "${PROJECT_ROOT}/${m}" ]; then
    signals+=("$m")
    has_codebase=true
  fi
done

if [ -d "${PROJECT_ROOT}/.git" ]; then
  signals+=(".git")
  if command -v git >/dev/null 2>&1; then
    # grep exits 1 on no-match; tolerate that under pipefail.
    tracked_count=$(
      cd "$PROJECT_ROOT" || exit 0
      { git ls-files 2>/dev/null \
        | grep -E "$SOURCE_EXT_REGEX" \
        | grep -vE "$IGNORE_REGEX" \
        || true; } | wc -l | tr -d ' '
    )
    [ "${tracked_count:-0}" -gt 0 ] && has_codebase=true
  fi
fi

# Build JSON output (jq for safe quoting; handle empty array under set -u)
if [ "${#signals[@]}" -eq 0 ]; then
  signals_json='[]'
else
  signals_json=$(printf '%s\n' "${signals[@]}" | jq -R . | jq -s .)
fi
jq -n \
  --argjson hc "$has_codebase" \
  --argjson sig "$signals_json" \
  --argjson tc  "$tracked_count" \
  '{has_codebase: $hc, signals: $sig, tracked_count: $tc}'
