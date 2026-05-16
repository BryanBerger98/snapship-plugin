#!/usr/bin/env bash
# tickets-adapter.sh — abstraction over GitHub / GitLab / JIRA tickets.
#
# Actions: create | get | update | comment | comment-pr | list
#          | set-issue-type | add-to-project | set-project-field   (github only)
#
# Platform routing:
#   - github → shells out to `gh` CLI (GraphQL via `gh api graphql` for native fields)
#   - gitlab → shells out to `glab` CLI
#   - jira   → emits MCP descriptor on stdout, exits 10 (skill executes call)
#
# Dry-run: write actions (create/update/comment/comment-pr) skip the underlying
# call, log to telemetry, and return a mock success result. Reads (get/list)
# run normally even with dry-run set.
#
# `comment-pr` semantics:
#   - github: `gh pr comment <PR-ID>`. Plain comment (not a code review).
#   - gitlab: `glab mr note <MR-ID>`. MR-level comment.
#   - jira:   no PR concept — caller must redirect to `comment` on the parent
#             ticket. Adapter exits 1 with `not_supported` for jira; the skill
#             handles that by falling back to per-ticket comments.
#
# Output JSON shapes:
#   ok:   {"ok":true, "mode":"cli|mcp|dry-run", "action":..., "platform":..., "result":{...}}
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   err:  {"ok":false, "error":"..."}                                            exit 1
#
# Exit codes: 0=ok, 1=error, 2=bad args, 10=MCP descriptor emitted

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"
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
PR_ID=""
BODY_FILE=""
ISSUE_TYPE=""
PROJECT_ID=""
FIELD_ID=""
OPTION_ID=""
VALUE_TEXT=""
ITEM_ID=""
DRY_RUN="${SNAP_DRY_RUN:-false}"
MODE="auto"

usage() {
  cat <<EOF
Usage: tickets-adapter.sh --action=ACTION [OPTIONS]

Actions: create | get | update | comment | comment-pr | list
         set-issue-type | add-to-project | set-project-field   (github only)

Required per action:
  create            --title (--body, --labels, --assignees optional)
  get               --ticket-id
  update            --ticket-id (any of --title/--body/--labels/--state)
  comment           --ticket-id (--comment | --body-file)
  comment-pr        --pr-id (--comment | --body-file)   github/gitlab only
  list              (--state, --labels, --assignees, --limit optional)
  set-issue-type    --ticket-id --issue-type=NAME      github only
  add-to-project    --ticket-id --project-id=PVT_xxx   github only (echoes item_id)
  set-project-field --item-id --project-id --field-id --option-id   github only

Options:
  --platform=github|gitlab|jira  Override config.tickets.platform
  --project-root=PATH            Project root (default: \$PWD)
  --ticket-id=ID                 Platform ID (e.g., 42, PROJ-3)
  --pr-id=ID                     PR/MR number for comment-pr
  --title=TEXT
  --body=TEXT
  --body-file=PATH               Read body/comment from file (mutually exclusive with --comment)
  --labels=CSV
  --assignees=CSV
  --state=open|closed
  --limit=N                      For list (default 50)
  --comment=TEXT                 For comment / comment-pr actions
  --issue-type=NAME              For set-issue-type (e.g., Feature, Bug, Epic)
  --project-id=ID                Project v2 node ID (PVT_xxx)
  --field-id=ID                  Project v2 single-select field ID (PVTSSF_xxx)
  --option-id=ID                 Project v2 single-select option ID
  --value=TEXT                   Free-text value for non-single-select fields (number/date/text)
  --item-id=ID                   Project v2 item ID (issue inside project)
  --dry-run                      Skip writes; equivalent to \$SNAP_DRY_RUN=1
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
    --pr-id=*)         PR_ID="${1#--pr-id=}" ;;
    --body-file=*)     BODY_FILE="${1#--body-file=}" ;;
    --issue-type=*)    ISSUE_TYPE="${1#--issue-type=}" ;;
    --project-id=*)    PROJECT_ID="${1#--project-id=}" ;;
    --field-id=*)      FIELD_ID="${1#--field-id=}" ;;
    --option-id=*)     OPTION_ID="${1#--option-id=}" ;;
    --value=*)         VALUE_TEXT="${1#--value=}" ;;
    --item-id=*)       ITEM_ID="${1#--item-id=}" ;;
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
  create|get|update|comment|comment-pr|list) ;;
  set-issue-type|add-to-project|set-project-field) ;;
  *) echo "ERROR: invalid --action: $ACTION" >&2; exit 2 ;;
esac

# Resolve --body-file → COMMENT_TEXT for comment / comment-pr
if [ -n "$BODY_FILE" ] && [ -z "$COMMENT_TEXT" ]; then
  [ -f "$BODY_FILE" ] || { echo "ERROR: --body-file not found: $BODY_FILE" >&2; exit 2; }
  COMMENT_TEXT=$(cat "$BODY_FILE")
fi

case "$MODE" in auto|cli|mcp) ;; *) echo "ERROR: bad --mode: $MODE" >&2; exit 2 ;; esac

# Resolve platform from config when omitted
if [ -z "$PLATFORM" ] && [ -f "${PROJECT_ROOT}/snap.config.json" ]; then
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
    --arg pr_id "${PR_ID:-}" \
    --arg title "$TITLE" \
    --arg body "$BODY" \
    --arg state "${STATE:-open}" \
    --arg comment "$COMMENT_TEXT" \
    --arg issue_type "$ISSUE_TYPE" \
    --arg project_id "$PROJECT_ID" \
    --arg field_id "$FIELD_ID" \
    --arg option_id "$OPTION_ID" \
    --arg value "$VALUE_TEXT" \
    --arg item_id "${ITEM_ID:-DRY-ITEM-0}" \
    --argjson labels    "$(csv_to_array "$LABELS_CSV")" \
    --argjson assignees "$(csv_to_array "$ASSIGNEES_CSV")" '
    {dry_run:true, action:$act, platform_id:$pid, pr_id:$pr_id, title:$title, body:$body, state:$state,
     comment:$comment, labels:$labels, assignees:$assignees,
     issue_type:$issue_type, project_id:$project_id, field_id:$field_id, option_id:$option_id,
     value:$value, item_id:$item_id}')
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
    --arg pr_id "$PR_ID" \
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
          | if $pr_id   != "" then .pr_id     = $pr_id   else . end
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

if [ "$ACTION" = "comment-pr" ] && [ "$PLATFORM" = "jira" ]; then
  jq -nc '{ok:false, error:"not_supported", reason:"jira platform has no PR concept; use action=comment on the parent ticket instead"}'
  exit 1
fi

case "$ACTION" in
  set-issue-type|add-to-project|set-project-field)
    if [ "$PLATFORM" != "github" ]; then
      jq -nc --arg act "$ACTION" --arg p "$PLATFORM" \
        '{ok:false, error:"not_supported", reason:($act + " only supported on github (got: " + $p + ")")}'
      exit 1
    fi
    ;;
esac

if [ "$MODE" = "mcp" ] || [ "$PLATFORM" = "jira" ]; then
  emit_mcp_descriptor
fi

# --- CLI dispatch (github via gh, gitlab via glab) ------------------------

# Allow tests to override the CLI binary via $SNAP_GH_BIN / $SNAP_GLAB_BIN
gh_bin()   { echo "${SNAP_GH_BIN:-gh}"; }
glab_bin() { echo "${SNAP_GLAB_BIN:-glab}"; }

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
    comment-pr)
      need "$PR_ID" "pr-id required for comment-pr"
      need "$COMMENT_TEXT" "comment text or --body-file required"
      local out; out=$("$bin" pr comment "$PR_ID" --body "$COMMENT_TEXT" 2>&1) \
        || { err_out "gh pr comment failed: $out"; exit 1; }
      jq -nc --arg pid "$PR_ID" --arg url "$out" '{pr_id:$pid, comment_url:$url}' \
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
    set-issue-type)
      need "$TICKET_ID" "ticket-id required for set-issue-type"
      need "$ISSUE_TYPE" "issue-type required (e.g., Feature, Bug, Epic)"
      local repo_full owner name node_id type_id
      repo_full=$("$bin" repo view --json nameWithOwner -q .nameWithOwner 2>&1) \
        || { err_out "gh repo view failed: $repo_full"; exit 1; }
      owner="${repo_full%%/*}"; name="${repo_full#*/}"
      # Resolve issue node ID + the org issue type ID matching $ISSUE_TYPE
      local resolve_q='query($o:String!,$n:String!,$num:Int!){
        repository(owner:$o,name:$n){
          issue(number:$num){ id }
          issueTypes(first:50){ nodes{ id name } }
        }
      }'
      local resolved
      resolved=$("$bin" api graphql -f query="$resolve_q" \
                  -F o="$owner" -F n="$name" -F num="$TICKET_ID" 2>&1) \
        || { err_out "gh graphql resolve failed: $resolved"; exit 1; }
      node_id=$(echo "$resolved" | jq -r '.data.repository.issue.id // ""')
      type_id=$(echo "$resolved" | jq -r --arg t "$ISSUE_TYPE" \
        '(.data.repository.issueTypes.nodes // []) | map(select(.name==$t)) | .[0].id // ""')
      [ -n "$node_id" ] || { err_out "issue #$TICKET_ID not found"; exit 1; }
      [ -n "$type_id" ] || { err_out "issue type \"$ISSUE_TYPE\" not available on org"; exit 1; }
      local mut_q='mutation($iid:ID!,$tid:ID!){
        updateIssueIssueType(input:{issueId:$iid,issueTypeId:$tid}){ issue{ id issueType{ name } } }
      }'
      local mut_out
      mut_out=$("$bin" api graphql -f query="$mut_q" \
                -F iid="$node_id" -F tid="$type_id" 2>&1) \
        || { err_out "gh graphql updateIssueIssueType failed: $mut_out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg t "$ISSUE_TYPE" \
        '{platform_id:$pid, issue_type:$t}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    add-to-project)
      need "$TICKET_ID" "ticket-id required for add-to-project"
      need "$PROJECT_ID" "project-id required (PVT_xxx)"
      local repo_full owner name node_id
      repo_full=$("$bin" repo view --json nameWithOwner -q .nameWithOwner 2>&1) \
        || { err_out "gh repo view failed: $repo_full"; exit 1; }
      owner="${repo_full%%/*}"; name="${repo_full#*/}"
      local resolve_q='query($o:String!,$n:String!,$num:Int!){
        repository(owner:$o,name:$n){ issue(number:$num){ id } }
      }'
      local resolved
      resolved=$("$bin" api graphql -f query="$resolve_q" \
                  -F o="$owner" -F n="$name" -F num="$TICKET_ID" 2>&1) \
        || { err_out "gh graphql resolve failed: $resolved"; exit 1; }
      node_id=$(echo "$resolved" | jq -r '.data.repository.issue.id // ""')
      [ -n "$node_id" ] || { err_out "issue #$TICKET_ID not found"; exit 1; }
      local mut_q='mutation($pid:ID!,$cid:ID!){
        addProjectV2ItemById(input:{projectId:$pid,contentId:$cid}){ item{ id } }
      }'
      local mut_out item_id
      mut_out=$("$bin" api graphql -f query="$mut_q" \
                -F pid="$PROJECT_ID" -F cid="$node_id" 2>&1) \
        || { err_out "gh graphql addProjectV2ItemById failed: $mut_out"; exit 1; }
      item_id=$(echo "$mut_out" | jq -r '.data.addProjectV2ItemById.item.id // ""')
      [ -n "$item_id" ] || { err_out "addProjectV2ItemById returned no item id"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg proj "$PROJECT_ID" --arg item "$item_id" \
        '{platform_id:$pid, project_id:$proj, item_id:$item}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    set-project-field)
      need "$ITEM_ID" "item-id required for set-project-field"
      need "$PROJECT_ID" "project-id required"
      need "$FIELD_ID" "field-id required"
      [ -n "$OPTION_ID" ] || [ -n "$VALUE_TEXT" ] || \
        { err_out "either --option-id or --value required for set-project-field"; exit 2; }
      local mut_out
      if [ -n "$OPTION_ID" ]; then
        local mut_q='mutation($pid:ID!,$iid:ID!,$fid:ID!,$opt:String!){
          updateProjectV2ItemFieldValue(input:{
            projectId:$pid, itemId:$iid, fieldId:$fid,
            value:{ singleSelectOptionId:$opt }
          }){ projectV2Item{ id } }
        }'
        mut_out=$("$bin" api graphql -f query="$mut_q" \
                  -F pid="$PROJECT_ID" -F iid="$ITEM_ID" -F fid="$FIELD_ID" -F opt="$OPTION_ID" 2>&1) \
          || { err_out "gh graphql updateProjectV2ItemFieldValue (single-select) failed: $mut_out"; exit 1; }
      else
        local mut_q='mutation($pid:ID!,$iid:ID!,$fid:ID!,$v:String!){
          updateProjectV2ItemFieldValue(input:{
            projectId:$pid, itemId:$iid, fieldId:$fid,
            value:{ text:$v }
          }){ projectV2Item{ id } }
        }'
        mut_out=$("$bin" api graphql -f query="$mut_q" \
                  -F pid="$PROJECT_ID" -F iid="$ITEM_ID" -F fid="$FIELD_ID" -F v="$VALUE_TEXT" 2>&1) \
          || { err_out "gh graphql updateProjectV2ItemFieldValue (text) failed: $mut_out"; exit 1; }
      fi
      jq -nc --arg item "$ITEM_ID" --arg fid "$FIELD_ID" --arg opt "$OPTION_ID" --arg v "$VALUE_TEXT" \
        '{item_id:$item, field_id:$fid, option_id:$opt, value:$v, updated:true}' \
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
    comment-pr)
      need "$PR_ID" "pr-id required for comment-pr"
      need "$COMMENT_TEXT" "comment text or --body-file required"
      local out; out=$("$bin" mr note "$PR_ID" --message "$COMMENT_TEXT" 2>&1) \
        || { err_out "glab mr note failed: $out"; exit 1; }
      jq -nc --arg pid "$PR_ID" '{pr_id:$pid, comment:true}' \
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
