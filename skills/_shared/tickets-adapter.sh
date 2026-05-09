#!/usr/bin/env bash
# tickets-adapter.sh — abstraction over GitHub / GitLab / JIRA tickets.
#
# Actions: create | get | update | comment | list
#
# Platform routing:
#   - github → shells out to `gh` CLI
#   - gitlab → shells out to `glab` CLI
#   - jira   → emits MCP descriptor on stdout, exits 10 (skill executes call)
#
# Dry-run: write actions (create/update/comment) skip the underlying call,
# log to telemetry, and return a mock success result. Reads (get/list) run
# normally even with dry-run set.
#
# Output JSON shapes:
#   ok:   {"ok":true, "mode":"cli|mcp|dry-run", "action":..., "platform":..., "result":{...}}
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   err:  {"ok":false, "error":"..."}                                            exit 1
#
# Exit codes: 0=ok, 1=error, 2=bad args, 10=MCP descriptor emitted

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"
ACTION=""
PLATFORM=""
TICKET_ID=""
TITLE=""
BODY=""
LABELS_CSV=""
ASSIGNEES_CSV=""
STATE=""
LIMIT="50"
COMMENT_TEXT=""
DRY_RUN="${ARTYSAN_DRY_RUN:-false}"
MODE="auto"

usage() {
  cat <<EOF
Usage: tickets-adapter.sh --action=ACTION [OPTIONS]

Actions: create | get | update | comment | list

Required per action:
  create   --title (--body, --labels, --assignees optional)
  get      --ticket-id
  update   --ticket-id (any of --title/--body/--labels/--state)
  comment  --ticket-id --comment
  list     (--state, --labels, --assignees, --limit optional)

Options:
  --platform=github|gitlab|jira  Override config.tickets.platform
  --project-root=PATH            Project root (default: \$PWD)
  --ticket-id=ID                 Platform ID (e.g., 42, PROJ-3)
  --title=TEXT
  --body=TEXT
  --labels=CSV
  --assignees=CSV
  --state=open|closed
  --limit=N                      For list (default 50)
  --comment=TEXT                 For comment action
  --dry-run                      Skip writes; equivalent to \$ARTYSAN_DRY_RUN=1
  --mode=auto|cli|mcp            Force routing (default auto)
  -h, --help                     Show this help
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --action=*)        ACTION="${1#--action=}" ;;
    --platform=*)      PLATFORM="${1#--platform=}" ;;
    --project-root=*)  PROJECT_ROOT="${1#--project-root=}" ;;
    --ticket-id=*)     TICKET_ID="${1#--ticket-id=}" ;;
    --title=*)         TITLE="${1#--title=}" ;;
    --body=*)          BODY="${1#--body=}" ;;
    --labels=*)        LABELS_CSV="${1#--labels=}" ;;
    --assignees=*)     ASSIGNEES_CSV="${1#--assignees=}" ;;
    --state=*)         STATE="${1#--state=}" ;;
    --limit=*)         LIMIT="${1#--limit=}" ;;
    --comment=*)       COMMENT_TEXT="${1#--comment=}" ;;
    --dry-run)         DRY_RUN="true" ;;
    --mode=*)          MODE="${1#--mode=}" ;;
    -h|--help)         usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[ -z "$ACTION" ] && { echo "ERROR: --action required" >&2; exit 2; }

case "$ACTION" in
  create|get|update|comment|list) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

case "$MODE" in auto|cli|mcp) ;; *) echo "ERROR: bad --mode: $MODE" >&2; exit 2 ;; esac

# Resolve platform from config when omitted
if [ -z "$PLATFORM" ] && [ -f "${PROJECT_ROOT}/artysan.config.json" ]; then
  if [ -x "${SCRIPT_DIR}/load-config.sh" ]; then
    CFG=$(bash "${SCRIPT_DIR}/load-config.sh" --project-root="$PROJECT_ROOT" --no-validate 2>/dev/null || echo '{}')
    PLATFORM=$(echo "$CFG" | jq -r '.tickets.platform // ""')
  fi
fi

[ -z "$PLATFORM" ] && { echo "ERROR: --platform required (or set tickets.platform in config)" >&2; exit 2; }

case "$PLATFORM" in
  github|gitlab|jira) ;;
  *) echo "ERROR: unsupported platform: $PLATFORM" >&2; exit 2 ;;
esac

# CSV → JSON array helper
csv_to_array() {
  local csv="$1"
  if [ -z "$csv" ]; then echo '[]'; else printf '%s' "$csv" | jq -Rc 'split(",") | map(select(length > 0))'; fi
}

ok_result() {
  local mode="$1" result_json="$2"
  jq -nc --arg mode "$mode" --arg act "$ACTION" --arg plat "$PLATFORM" \
    --argjson r "$result_json" '
    {ok:true, mode:$mode, action:$act, platform:$plat, result:$r}'
}

err_out() {
  local msg="$1"
  jq -nc --arg m "$msg" '{ok:false, error:$m}'
}

# Required field check helpers
need() { [ -n "$1" ] || { echo "$(err_out "$2")"; exit 2; }; }

# --- DRY RUN write shortcut ----------------------------------------------
if [ "$DRY_RUN" = "true" ] && [ "$ACTION" != "get" ] && [ "$ACTION" != "list" ]; then
  MOCK=$(jq -nc \
    --arg act "$ACTION" \
    --arg pid "${TICKET_ID:-DRY-0}" \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg state "${STATE:-open}" \
    --arg comment "$COMMENT_TEXT" \
    --argjson labels    "$(csv_to_array "$LABELS_CSV")" \
    --argjson assignees "$(csv_to_array "$ASSIGNEES_CSV")" '
    {dry_run:true, action:$act, platform_id:$pid, title:$title, body:$body, state:$state,
     comment:$comment, labels:$labels, assignees:$assignees}')
  ok_result "dry-run" "$MOCK"
  exit 0
fi

# --- MCP descriptor (jira platform or --mode=mcp) -------------------------
emit_mcp_descriptor() {
  local result
  result=$(jq -nc \
    --arg act "$ACTION" \
    --arg plat "$PLATFORM" \
    --arg pid  "$TICKET_ID" \
    --arg title "$TITLE" \
    --arg body  "$BODY" \
    --arg state "$STATE" \
    --arg limit "$LIMIT" \
    --arg comment "$COMMENT_TEXT" \
    --argjson labels    "$(csv_to_array "$LABELS_CSV")" \
    --argjson assignees "$(csv_to_array "$ASSIGNEES_CSV")" '
    {
      ok:false, mode:"mcp", reason:"mcp_required",
      descriptor: {
        platform: $plat, action: $act,
        params: (
          {}
          | if $pid     != "" then .ticket_id = $pid     else . end
          | if $title   != "" then .title     = $title   else . end
          | if $body    != "" then .body      = $body    else . end
          | if $state   != "" then .state     = $state   else . end
          | if $comment != "" then .comment   = $comment else . end
          | if ($labels    | length) > 0 then .labels    = $labels    else . end
          | if ($assignees | length) > 0 then .assignees = $assignees else . end
          | if $act == "list" then .limit = ($limit | tonumber) else . end
        )
      }
    }')
  echo "$result"
  exit 10
}

if [ "$MODE" = "mcp" ] || [ "$PLATFORM" = "jira" ]; then
  emit_mcp_descriptor
fi

# --- CLI dispatch (github via gh, gitlab via glab) ------------------------

# Allow tests to override the CLI binary via $ARTYSAN_GH_BIN / $ARTYSAN_GLAB_BIN
gh_bin()   { echo "${ARTYSAN_GH_BIN:-gh}"; }
glab_bin() { echo "${ARTYSAN_GLAB_BIN:-glab}"; }

# Normalize a github JSON issue → ticket schema fields (best-effort subset)
normalize_github_issue() {
  jq '{
    platform_id: (.number | tostring),
    url: .url,
    title: .title,
    description: (.body // ""),
    status: (
      if .state == "OPEN"   then "todo"
      elif .state == "CLOSED" then "done"
      else "todo" end),
    labels:    (.labels    // [] | map(.name // .)),
    assignees: (.assignees // [] | map(.login // .))
  }'
}

normalize_gitlab_issue() {
  jq '{
    platform_id: (.iid | tostring),
    url: .web_url,
    title: .title,
    description: (.description // ""),
    status: (
      if .state == "opened" then "todo"
      elif .state == "closed" then "done"
      else "todo" end),
    labels:    (.labels    // []),
    assignees: ((.assignees // []) | map(.username))
  }'
}

run_github() {
  local bin; bin=$(gh_bin)
  command -v "$bin" >/dev/null 2>&1 || { err_out "gh CLI not installed"; exit 1; }

  case "$ACTION" in
    create)
      need "$TITLE" "title required for create"
      local args=(issue create --title "$TITLE")
      [ -n "$BODY" ]          && args+=(--body "$BODY")
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      [ -n "$ASSIGNEES_CSV" ] && args+=(--assignee "$ASSIGNEES_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "gh create failed: $out"; exit 1; }
      # gh issue create echoes the URL on success
      local url="${out##*$'\n'}"
      local num="${url##*/}"
      jq -nc --arg url "$url" --arg num "$num" --arg title "$TITLE" '
        {platform_id:$num, url:$url, title:$title, status:"todo"}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    get)
      need "$TICKET_ID" "ticket-id required for get"
      local out; out=$("$bin" issue view "$TICKET_ID" --json number,url,title,body,state,labels,assignees 2>&1) \
        || { err_out "gh get failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | normalize_github_issue)
      ok_result "cli" "$norm"
      ;;
    update)
      need "$TICKET_ID" "ticket-id required for update"
      local args=(issue edit "$TICKET_ID")
      [ -n "$TITLE" ]      && args+=(--title "$TITLE")
      [ -n "$BODY" ]       && args+=(--body "$BODY")
      [ -n "$LABELS_CSV" ] && args+=(--add-label "$LABELS_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "gh update failed: $out"; exit 1; }
      [ "$STATE" = "closed" ] && { "$bin" issue close "$TICKET_ID" >/dev/null 2>&1 || true; }
      [ "$STATE" = "open" ]   && { "$bin" issue reopen "$TICKET_ID" >/dev/null 2>&1 || true; }
      jq -nc --arg pid "$TICKET_ID" '{platform_id:$pid, updated:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    comment)
      need "$TICKET_ID" "ticket-id required for comment"
      need "$COMMENT_TEXT" "comment text required"
      local out; out=$("$bin" issue comment "$TICKET_ID" --body "$COMMENT_TEXT" 2>&1) \
        || { err_out "gh comment failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg url "$out" '{platform_id:$pid, comment_url:$url}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list)
      local fields="number,url,title,body,state,labels,assignees"
      local args=(issue list --json "$fields" --limit "$LIMIT")
      [ -n "$STATE" ]         && args+=(--state "$STATE")
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      [ -n "$ASSIGNEES_CSV" ] && args+=(--assignee "$ASSIGNEES_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "gh list failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | '"$(echo '{
        platform_id: (.number | tostring),
        url: .url,
        title: .title,
        description: (.body // ""),
        status: (if .state == "OPEN" then "todo" elif .state == "CLOSED" then "done" else "todo" end),
        labels: ((.labels // []) | map(.name // .)),
        assignees: ((.assignees // []) | map(.login // .))
      }')"']')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
  esac
}

run_gitlab() {
  local bin; bin=$(glab_bin)
  command -v "$bin" >/dev/null 2>&1 || { err_out "glab CLI not installed"; exit 1; }

  case "$ACTION" in
    create)
      need "$TITLE" "title required for create"
      local args=(issue create --title "$TITLE")
      [ -n "$BODY" ]          && args+=(--description "$BODY")
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      [ -n "$ASSIGNEES_CSV" ] && args+=(--assignee "$ASSIGNEES_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "glab create failed: $out"; exit 1; }
      local url; url=$(printf '%s\n' "$out" | grep -oE 'https?://[^[:space:]]+' | tail -1)
      local iid="${url##*/}"
      jq -nc --arg url "$url" --arg iid "$iid" --arg title "$TITLE" '
        {platform_id:$iid, url:$url, title:$title, status:"todo"}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    get)
      need "$TICKET_ID" "ticket-id required for get"
      local out; out=$("$bin" issue view "$TICKET_ID" --output json 2>&1) \
        || { err_out "glab get failed: $out"; exit 1; }
      ok_result "cli" "$(echo "$out" | normalize_gitlab_issue)"
      ;;
    update)
      need "$TICKET_ID" "ticket-id required for update"
      local args=(issue update "$TICKET_ID")
      [ -n "$TITLE" ]      && args+=(--title "$TITLE")
      [ -n "$BODY" ]       && args+=(--description "$BODY")
      [ -n "$LABELS_CSV" ] && args+=(--label "$LABELS_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "glab update failed: $out"; exit 1; }
      [ "$STATE" = "closed" ] && { "$bin" issue close  "$TICKET_ID" >/dev/null 2>&1 || true; }
      [ "$STATE" = "open" ]   && { "$bin" issue reopen "$TICKET_ID" >/dev/null 2>&1 || true; }
      jq -nc --arg pid "$TICKET_ID" '{platform_id:$pid, updated:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    comment)
      need "$TICKET_ID" "ticket-id required for comment"
      need "$COMMENT_TEXT" "comment text required"
      local out; out=$("$bin" issue note "$TICKET_ID" --message "$COMMENT_TEXT" 2>&1) \
        || { err_out "glab comment failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" '{platform_id:$pid, comment:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list)
      local args=(issue list --output json --per-page "$LIMIT")
      [ "$STATE" = "open" ]   && args+=(--opened)
      [ "$STATE" = "closed" ] && args+=(--closed)
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      local out; out=$("$bin" "${args[@]}" 2>&1) || { err_out "glab list failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {
        platform_id: (.iid | tostring),
        url: .web_url,
        title: .title,
        description: (.description // ""),
        status: (if .state == "opened" then "todo" elif .state == "closed" then "done" else "todo" end),
        labels: (.labels // []),
        assignees: ((.assignees // []) | map(.username))
      }]')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
  esac
}

case "$PLATFORM" in
  github) run_github ;;
  gitlab) run_gitlab ;;
esac
