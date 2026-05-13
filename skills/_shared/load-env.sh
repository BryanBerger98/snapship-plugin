#!/usr/bin/env bash
# load-env.sh — read `.env.snapship` at project root (KEY=VALUE format).
#
# Usage:
#   bash load-env.sh --project-root=PATH --key=NAME
#     → print value of NAME from <PATH>/.env.snapship on stdout. Exit 1 if file
#       missing or key absent.
#   bash load-env.sh --project-root=PATH
#     → print all non-comment KEY=VALUE lines on stdout (suitable for `eval`).
#
# Parsing rules:
#   - lines matching `^[[:space:]]*#` ignored (comments).
#   - blank lines ignored.
#   - first `=` splits key/value.
#   - surrounding `"…"` or `'…'` quotes stripped from value.
#   - no shell substitution / no `export` prefix support — keep it dumb on
#     purpose (secrets file, not a shell script).

set -euo pipefail

PROJECT_ROOT=""
KEY=""

for arg in "$@"; do
  case "$arg" in
    --project-root=*) PROJECT_ROOT="${arg#*=}" ;;
    --key=*) KEY="${arg#*=}" ;;
    *)
      echo "load-env.sh: unknown arg: $arg" >&2
      exit 2
      ;;
  esac
done

if [ -z "$PROJECT_ROOT" ]; then
  echo "load-env.sh: --project-root required" >&2
  exit 2
fi

ENV_FILE="$PROJECT_ROOT/.env.snapship"
if [ ! -f "$ENV_FILE" ]; then
  echo "load-env.sh: $ENV_FILE not found" >&2
  exit 1
fi

strip_quotes() {
  local v="$1"
  if [[ "$v" =~ ^\".*\"$ ]] || [[ "$v" =~ ^\'.*\'$ ]]; then
    v="${v:1:${#v}-2}"
  fi
  printf '%s' "$v"
}

found=1
while IFS= read -r line || [ -n "$line" ]; do
  # strip leading whitespace for detection
  trimmed="${line#"${line%%[![:space:]]*}"}"
  [ -z "$trimmed" ] && continue
  case "$trimmed" in \#*) continue ;; esac
  [[ "$trimmed" == *"="* ]] || continue

  name="${trimmed%%=*}"
  # trim trailing whitespace from name
  name="${name%"${name##*[![:space:]]}"}"
  value="${trimmed#*=}"
  value="$(strip_quotes "$value")"

  if [ -n "$KEY" ]; then
    if [ "$name" = "$KEY" ]; then
      printf '%s\n' "$value"
      found=0
      break
    fi
  else
    printf '%s=%s\n' "$name" "$value"
    found=0
  fi
done < "$ENV_FILE"

if [ -n "$KEY" ] && [ "$found" -ne 0 ]; then
  echo "load-env.sh: key '$KEY' not found in $ENV_FILE" >&2
  exit 1
fi

exit 0
