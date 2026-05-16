#!/usr/bin/env bash
# cache-runtime.sh — Ephemeral per-subject runtime cache .snap/.runtime/<subject-id>/
#
# v1.2 contract — skills (/ticket, /develop, /qa) use a runtime cache scoped to
# a "subject" (story_id, batch standalone, …) for drafts, multi-turn state and
# validation. Cache is purged immediately at end of skill (success or failure).
# Source of truth remains the tracker; cache is volatile.
#
# Concurrent isolation : each invocation generates its own subject-id, so two
# parallel /ticket runs on the same story never collide.
#
# Trap pattern expected from callers :
#   SUBJECT_ID=$(skills/_shared/cache-runtime.sh id-gen --prefix=ticket)
#   skills/_shared/cache-runtime.sh init "$SUBJECT_ID"
#   trap 'skills/_shared/cache-runtime.sh purge "'$SUBJECT_ID'"' EXIT
#
# Subcommands:
#   init <subject-id>               Create .snap/.runtime/<subject-id>/ (idempotent).
#   path <subject-id>               Print absolute directory path.
#   write <subject-id> <file>       Read content from stdin, write to file.
#   read  <subject-id> <file>       Print file content to stdout (exit 1 if absent).
#   exists <subject-id> [<file>]    Exit 0 if subject (or file) exists, else 1.
#   purge <subject-id>              Trash directory (no rm). Idempotent.
#   id-gen [--prefix=NAME]          Print unique subject-id (prefix-YYYYMMDDTHHMMSS-XXXXXX).
#
# Common options:
#   --project-root=PATH             Default: $SNAP_PROJECT_ROOT or $PWD.
#   -h, --help                      Show this help.
#
# Exit codes: 0=ok, 1=invalid arg / missing file, 2=jq/io error.

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

usage() {
  sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

[ $# -lt 1 ] && { usage >&2; exit 1; }

CMD="$1"; shift

PREFIX=""
ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*) PROJECT_ROOT="${1#--project-root=}" ;;
    --prefix=*)       PREFIX="${1#--prefix=}" ;;
    -h|--help)        usage; exit 0 ;;
    --) shift; ARGS+=("$@"); break ;;
    -*) echo "ERROR: unknown flag: $1" >&2; usage >&2; exit 1 ;;
    *)  ARGS+=("$1") ;;
  esac
  shift
done

RUNTIME_ROOT="${PROJECT_ROOT}/.snap/.runtime"

validate_subject_id() {
  local id="$1"
  if [[ ! "$id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: subject-id '${id}' must match ^[A-Za-z0-9][A-Za-z0-9._-]*\$" >&2
    exit 1
  fi
  # Defense in depth — prevent traversal via .. or absolute components.
  case "$id" in
    *..*|*/*) echo "ERROR: subject-id must not contain '..' or '/'" >&2; exit 1 ;;
  esac
}

subject_dir() {
  echo "${RUNTIME_ROOT}/$1"
}

warn_gitignore() {
  local gi="${PROJECT_ROOT}/.gitignore"
  if [ -f "$gi" ] && ! grep -qE '(^|/)\.snap/\.runtime/?' "$gi" \
     && ! grep -qE '(^|/)\.snap/\*' "$gi"; then
    echo "WARN: .snap/.runtime/ should be gitignored — add it to .gitignore" >&2
  fi
}

case "$CMD" in
  init)
    [ "${#ARGS[@]}" -eq 1 ] || { echo "ERROR: init <subject-id>" >&2; exit 1; }
    validate_subject_id "${ARGS[0]}"
    mkdir -p "$(subject_dir "${ARGS[0]}")"
    warn_gitignore
    ;;

  path)
    [ "${#ARGS[@]}" -eq 1 ] || { echo "ERROR: path <subject-id>" >&2; exit 1; }
    validate_subject_id "${ARGS[0]}"
    subject_dir "${ARGS[0]}"
    ;;

  write)
    [ "${#ARGS[@]}" -eq 2 ] || { echo "ERROR: write <subject-id> <file>" >&2; exit 1; }
    validate_subject_id "${ARGS[0]}"
    case "${ARGS[1]}" in
      /*|*/*|.|..|*..*) echo "ERROR: <file> must be a bare filename (no slash, no ..)" >&2; exit 1 ;;
    esac
    dir="$(subject_dir "${ARGS[0]}")"
    [ -d "$dir" ] || { echo "ERROR: subject '${ARGS[0]}' not initialized — run 'init' first" >&2; exit 1; }
    tmp="${dir}/.${ARGS[1]}.tmp.$$"
    cat > "$tmp"
    mv "$tmp" "${dir}/${ARGS[1]}"
    ;;

  read)
    [ "${#ARGS[@]}" -eq 2 ] || { echo "ERROR: read <subject-id> <file>" >&2; exit 1; }
    validate_subject_id "${ARGS[0]}"
    f="$(subject_dir "${ARGS[0]}")/${ARGS[1]}"
    [ -f "$f" ] || { echo "ERROR: ${f} not found" >&2; exit 1; }
    cat "$f"
    ;;

  exists)
    case "${#ARGS[@]}" in
      1)
        validate_subject_id "${ARGS[0]}"
        [ -d "$(subject_dir "${ARGS[0]}")" ]
        ;;
      2)
        validate_subject_id "${ARGS[0]}"
        [ -f "$(subject_dir "${ARGS[0]}")/${ARGS[1]}" ]
        ;;
      *) echo "ERROR: exists <subject-id> [<file>]" >&2; exit 1 ;;
    esac
    ;;

  purge)
    [ "${#ARGS[@]}" -eq 1 ] || { echo "ERROR: purge <subject-id>" >&2; exit 1; }
    validate_subject_id "${ARGS[0]}"
    dir="$(subject_dir "${ARGS[0]}")"
    if [ -e "$dir" ]; then
      if command -v trash >/dev/null 2>&1; then
        trash "$dir" 2>/dev/null || true
      else
        # Fallback : move to .snap/.trash/<timestamp> instead of rm.
        local_trash="${PROJECT_ROOT}/.snap/.trash"
        mkdir -p "$local_trash"
        mv "$dir" "${local_trash}/$(basename "$dir").$(date -u +%s)"
      fi
    fi
    ;;

  id-gen)
    ts=$(date -u +%Y%m%dT%H%M%S)
    # 6 hex chars from /dev/urandom — POSIX-friendly, no extra deps.
    rand=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 6 || true)
    [ -z "$rand" ] && rand=$(printf '%06x' "$RANDOM$$" | tail -c 6)
    if [ -n "$PREFIX" ]; then
      validate_subject_id "${PREFIX}-${ts}-${rand}"
      echo "${PREFIX}-${ts}-${rand}"
    else
      echo "${ts}-${rand}"
    fi
    ;;

  -h|--help)
    usage; exit 0
    ;;

  *)
    echo "ERROR: unknown subcommand: $CMD" >&2
    usage >&2
    exit 1
    ;;
esac
