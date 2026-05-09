#!/usr/bin/env bash
# detect-test-commands.sh — auto-detect test/lint/typecheck/format commands from project manifests.
#
# Inspects (in order, first match per slot wins):
#   - package.json      → npm/pnpm/yarn run scripts (test, lint, typecheck, format)
#   - Cargo.toml        → cargo test/clippy/fmt
#   - pyproject.toml    → pytest, mypy/pyright, ruff/flake8, black/ruff format
#   - Makefile          → make {test,lint,typecheck,format} (only if target exists)
#
# Output: JSON with up to 4 keys (test_command, typecheck_command, lint_command, format_command).
# Missing slots are omitted (not null).
#
# Exit codes: 0=ok (always when project root readable), 1=bad args
#
# Usage:
#   detect-test-commands.sh
#   detect-test-commands.sh --project-root=/path
#   detect-test-commands.sh --prefer=cargo

set -euo pipefail

PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"
PREFER=""

usage() {
  cat <<EOF
Usage: detect-test-commands.sh [OPTIONS]

Auto-detects test/lint/typecheck/format commands from project manifests.

Options:
  --project-root=PATH   Project root (default: \$PWD or \$ARTYSAN_PROJECT_ROOT)
  --prefer=ECOSYSTEM    Bias detection: npm|cargo|python|make (default: first found)
  -h, --help            Show this help

Output:
  JSON object on stdout: {"test_command":"...","lint_command":"...",...}
  Missing slots are omitted.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --prefer=*)       PREFER="${1#--prefer=}" ;;
    -h|--help)        usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -d "$PROJECT_ROOT" ] || { echo "ERROR: project root not a directory: $PROJECT_ROOT" >&2; exit 1; }

case "$PREFER" in
  ""|npm|cargo|python|make) ;;
  *) echo "ERROR: --prefer must be npm|cargo|python|make" >&2; exit 1 ;;
esac

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

# Detect npm package manager (priority: pnpm-lock > yarn.lock > bun.lockb > npm)
detect_pm() {
  if [ -f "$PROJECT_ROOT/pnpm-lock.yaml" ]; then echo "pnpm"
  elif [ -f "$PROJECT_ROOT/yarn.lock" ];   then echo "yarn"
  elif [ -f "$PROJECT_ROOT/bun.lockb" ];   then echo "bun"
  else echo "npm"
  fi
}

# Returns "1" if pkg-script exists, else empty
npm_has_script() {
  local script="$1"
  jq -er --arg s "$script" '.scripts[$s] // empty' "$PROJECT_ROOT/package.json" >/dev/null 2>&1 && echo "1" || echo ""
}

npm_run() {
  local script="$1"
  local pm; pm=$(detect_pm)
  case "$pm" in
    npm)   echo "npm run $script" ;;
    pnpm)  echo "pnpm run $script" ;;
    yarn)  echo "yarn $script" ;;
    bun)   echo "bun run $script" ;;
  esac
}

# Returns "1" if make target exists in Makefile
make_has_target() {
  local target="$1"
  if [ ! -f "$PROJECT_ROOT/Makefile" ]; then echo ""; return 0; fi
  if grep -E "^${target}:" "$PROJECT_ROOT/Makefile" >/dev/null 2>&1; then echo "1"; else echo ""; fi
}

# Returns "1" if regex matches in pyproject.toml
py_has() {
  local pattern="$1"
  if [ ! -f "$PROJECT_ROOT/pyproject.toml" ]; then echo ""; return 0; fi
  if grep -E "$pattern" "$PROJECT_ROOT/pyproject.toml" >/dev/null 2>&1; then echo "1"; else echo ""; fi
}

TEST=""
TYPECHECK=""
LINT=""
FORMAT=""

# Order of source attempts based on --prefer
if [ -n "$PREFER" ]; then
  ORDER=("$PREFER")
  for src in npm cargo python make; do
    [ "$src" != "$PREFER" ] && ORDER+=("$src")
  done
else
  ORDER=(npm cargo python make)
fi

try_npm() {
  [ -f "$PROJECT_ROOT/package.json" ] || return 0
  jq -e '.' "$PROJECT_ROOT/package.json" >/dev/null 2>&1 || return 0

  if [ -z "$TEST" ] && [ -n "$(npm_has_script test)" ]; then
    TEST=$(npm_run test)
  fi
  if [ -z "$TYPECHECK" ]; then
    for s in typecheck type-check tsc; do
      if [ -n "$(npm_has_script "$s")" ]; then
        TYPECHECK=$(npm_run "$s")
        break
      fi
    done
  fi
  if [ -z "$LINT" ]; then
    for s in lint eslint; do
      if [ -n "$(npm_has_script "$s")" ]; then
        LINT=$(npm_run "$s")
        break
      fi
    done
  fi
  if [ -z "$FORMAT" ]; then
    for s in format prettier; do
      if [ -n "$(npm_has_script "$s")" ]; then
        FORMAT=$(npm_run "$s")
        break
      fi
    done
  fi
  return 0
}

try_cargo() {
  [ -f "$PROJECT_ROOT/Cargo.toml" ] || return 0
  [ -z "$TEST" ]      && TEST="cargo test"
  [ -z "$TYPECHECK" ] && TYPECHECK="cargo check"
  [ -z "$LINT" ]      && LINT="cargo clippy -- -D warnings"
  [ -z "$FORMAT" ]    && FORMAT="cargo fmt"
  return 0
}

try_python() {
  [ -f "$PROJECT_ROOT/pyproject.toml" ] || return 0

  if [ -z "$TEST" ]; then
    if [ -n "$(py_has '\[tool\.pytest')" ] || [ -n "$(py_has 'pytest')" ]; then
      TEST="pytest"
    elif [ -d "$PROJECT_ROOT/tests" ] || [ -d "$PROJECT_ROOT/test" ]; then
      TEST="pytest"
    fi
  fi
  if [ -z "$TYPECHECK" ]; then
    if [ -n "$(py_has '\[tool\.mypy')" ] || [ -n "$(py_has 'mypy')" ]; then
      TYPECHECK="mypy ."
    elif [ -n "$(py_has 'pyright')" ]; then
      TYPECHECK="pyright"
    fi
  fi
  if [ -z "$LINT" ]; then
    if [ -n "$(py_has '\[tool\.ruff')" ] || [ -n "$(py_has 'ruff')" ]; then
      LINT="ruff check ."
    elif [ -n "$(py_has 'flake8')" ]; then
      LINT="flake8"
    fi
  fi
  if [ -z "$FORMAT" ]; then
    if [ -n "$(py_has '\[tool\.black')" ] || [ -n "$(py_has 'black')" ]; then
      FORMAT="black ."
    elif [ -n "$(py_has 'ruff')" ]; then
      FORMAT="ruff format ."
    fi
  fi
  return 0
}

try_make() {
  [ -f "$PROJECT_ROOT/Makefile" ] || return 0
  if [ -z "$TEST" ]      && [ -n "$(make_has_target test)" ];      then TEST="make test"; fi
  if [ -z "$TYPECHECK" ] && [ -n "$(make_has_target typecheck)" ]; then TYPECHECK="make typecheck"; fi
  if [ -z "$LINT" ]      && [ -n "$(make_has_target lint)" ];      then LINT="make lint"; fi
  if [ -z "$FORMAT" ]    && [ -n "$(make_has_target format)" ];    then FORMAT="make format"; fi
  return 0
}

for src in "${ORDER[@]}"; do
  case "$src" in
    npm)    try_npm ;;
    cargo)  try_cargo ;;
    python) try_python ;;
    make)   try_make ;;
  esac
done

jq -nc \
  --arg test "$TEST" \
  --arg tc "$TYPECHECK" \
  --arg lint "$LINT" \
  --arg fmt "$FORMAT" '
  {}
  | if $test != "" then .test_command      = $test else . end
  | if $tc   != "" then .typecheck_command = $tc   else . end
  | if $lint != "" then .lint_command      = $lint else . end
  | if $fmt  != "" then .format_command    = $fmt  else . end
'
