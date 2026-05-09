#!/usr/bin/env bash
# ask-or-default.sh — auto-mode shortcut wrapper for AskUserQuestion.
#
# Behavior:
#   --auto-mode=true  + --default     → prints default value on stdout, exit 0
#   --auto-mode=true  + no default    → exit 1 with diagnostic
#   --auto-mode=false                 → emits JSON instruction on stdout, exit 0
#                                       (skill orchestrates the AskUserQuestion tool call)
#
# Stdout (auto-mode=true): the default value, raw.
# Stdout (auto-mode=false): JSON {"action":"ask","question_id":"...","question":"...","options":[...],"default":"..."}.
#
# Usage:
#   ask-or-default.sh --auto-mode=true --question-id=confirm-platform --default=jira
#   ask-or-default.sh --auto-mode=false --question-id=confirm-platform \
#       --question="Quel platform?" --options=jira,github,gitlab --default=jira

set -euo pipefail

AUTO_MODE=""
QUESTION_ID=""
QUESTION=""
OPTIONS=""
DEFAULT=""
HEADER=""

usage() {
  cat <<EOF
Usage: ask-or-default.sh --auto-mode=true|false --question-id=ID [OPTIONS]

Auto-mode: prints --default on stdout (or fails if absent).
Interactive: emits JSON instruction so skill can invoke AskUserQuestion tool.

Required:
  --auto-mode=true|false  Auto-mode flag (state.auto_mode)
  --question-id=ID        Diagnostic label (e.g., "confirm-platform")

Optional:
  --question=TEXT         Question text (interactive only)
  --options=CSV           Comma-separated options
  --default=VALUE         Required when auto-mode=true
  --header=TEXT           Optional UI header (max 12 chars per AskUserQuestion contract)
  -h, --help              Show this help

Exit codes:
  0 = success
  1 = invalid arg / auto-mode without default
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --auto-mode=*)   AUTO_MODE="${1#--auto-mode=}" ;;
    --question-id=*) QUESTION_ID="${1#--question-id=}" ;;
    --question=*)    QUESTION="${1#--question=}" ;;
    --options=*)     OPTIONS="${1#--options=}" ;;
    --default=*)     DEFAULT="${1#--default=}" ;;
    --header=*)      HEADER="${1#--header=}" ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

[ -z "$AUTO_MODE" ]    && { echo "ERROR: --auto-mode required" >&2; exit 1; }
[ -z "$QUESTION_ID" ]  && { echo "ERROR: --question-id required" >&2; exit 1; }

case "$AUTO_MODE" in
  true|false) ;;
  *) echo "ERROR: --auto-mode must be true|false" >&2; exit 1 ;;
esac

if [ "$AUTO_MODE" = "true" ]; then
  if [ -z "$DEFAULT" ]; then
    echo "ERROR: auto-mode without default: question-id=${QUESTION_ID}" >&2
    exit 1
  fi
  # Optional: validate default is in options
  if [ -n "$OPTIONS" ]; then
    found=0
    IFS=',' read -ra opts <<< "$OPTIONS"
    for o in "${opts[@]}"; do
      [ "$o" = "$DEFAULT" ] && { found=1; break; }
    done
    if [ "$found" -ne 1 ]; then
      echo "ERROR: default '${DEFAULT}' not in options '${OPTIONS}': question-id=${QUESTION_ID}" >&2
      exit 1
    fi
  fi
  printf '%s\n' "$DEFAULT"
  exit 0
fi

# Interactive: emit JSON instruction for the skill
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

OPTS_JSON='[]'
if [ -n "$OPTIONS" ]; then
  OPTS_JSON=$(printf '%s' "$OPTIONS" | jq -Rc 'split(",")')
fi

jq -nc \
  --arg qid "$QUESTION_ID" \
  --arg question "$QUESTION" \
  --argjson options "$OPTS_JSON" \
  --arg default "$DEFAULT" \
  --arg header "$HEADER" '
  {action: "ask", question_id: $qid}
  | if $question != "" then .question = $question else . end
  | if ($options | length) > 0 then .options = $options else . end
  | if $default  != "" then .default = $default else . end
  | if $header   != "" then .header = $header else . end
'
