#!/usr/bin/env bash
# tickets-adapter.sh — abstraction over GitHub / GitLab / JIRA / Linear tickets.
#
# v1.2 — adds hierarchical push (Epic → Story → Task), live lookups,
# capability matrix, retry/timeout wrapper, idempotence guard.
#
# Actions (CRUD): create | get | update | comment | comment-pr | list
# Actions (native github): set-issue-type | add-to-project | set-project-field
# Actions (v1.2 hierarchy):
#   capabilities          → return capability JSON for platform
#   link-parent           → wire child ↔ parent (Sub-issue GH / Epic Link Jira / Linear parent / GitLab Epic)
#   set-milestone         → assign milestone/sprint
#   set-version           → assign fixVersion/Release (capability-gated)
#   list-epics            → live list of open epics (array)
#   list-milestones       → live list of milestones (capability-gated)
#   list-versions         → live list of versions (capability-gated)
#   close-epic            → close epic if all children done (capability-gated)
#
# Platform routing:
#   - github → shells out to `gh` CLI (GraphQL via `gh api graphql` for native fields)
#   - gitlab → shells out to `glab` CLI
#   - jira   → emits MCP descriptor on stdout, exits 10 (skill executes call)
#   - linear → emits MCP descriptor on stdout, exits 10 (no canonical CLI)
#
# Retry/timeout (decision O — hardcoded constants):
#   SNAP_TRACKER_RETRY_MAX=3, SNAP_TRACKER_BACKOFF_MS=1000, SNAP_TRACKER_TIMEOUT_S=30
#   Retry only on transient errors (5xx, 429, "rate limit", timeouts).
#
# Idempotence (decision 7b — hierarchical strict):
#   - `create` with `--idempotency-check=true` looks up by title before create.
#   - `link-parent` refuses if --parent-id empty or unresolved.
#
# Dry-run: write actions (create/update/comment/comment-pr/link-parent/
# set-milestone/set-version/close-epic) skip the underlying call, log, and
# return a mock success result. Reads (get/list*) run normally even with
# dry-run set.
#
# `comment-pr` semantics:
#   - github: `gh pr comment <PR-ID>`. Plain comment (not a code review).
#   - gitlab: `glab mr note <MR-ID>`. MR-level comment.
#   - jira/linear: no PR concept — caller must redirect to `comment` on the
#                  parent ticket. Adapter exits 1 with `not_supported`.
#
# Output JSON shapes:
#   ok:   {"ok":true, "mode":"cli|mcp|dry-run", "action":..., "platform":..., "result":{...}}
#   mcp:  {"ok":false,"mode":"mcp","reason":"mcp_required","descriptor":{...}}  exit 10
#   err:  {"ok":false, "error":"..."}                                            exit 1
#
# Exit codes: 0=ok, 1=error, 2=bad args, 10=MCP descriptor emitted

set -euo pipefail

# v1.2 — decision O : hardcoded defaults (overridable via env for tests).
RETRY_MAX="${SNAP_TRACKER_RETRY_MAX:-3}"
BACKOFF_MS="${SNAP_TRACKER_BACKOFF_MS:-1000}"
TIMEOUT_S="${SNAP_TRACKER_TIMEOUT_S:-30}"

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
PARENT_ID=""
PARENT_TYPE=""
CHILD_ID=""
MILESTONE=""
VERSION_NAME=""
STORY_TYPE=""
IDEMPOTENCY_CHECK="false"
DRY_RUN="${SNAP_DRY_RUN:-false}"
MODE="auto"

usage() {
  cat <<EOF
Usage: tickets-adapter.sh --action=ACTION [OPTIONS]

Actions: create | get | update | comment | comment-pr | list
         set-issue-type | add-to-project | set-project-field   (github only)
         capabilities | link-parent | set-milestone | set-version
         list-epics | list-milestones | list-versions | close-epic

Required per action:
  create            --title (--body, --labels, --assignees, --parent-id,
                    --idempotency-check optional)
  get               --ticket-id
  update            --ticket-id (any of --title/--body/--labels/--state)
  comment           --ticket-id (--comment | --body-file)
  comment-pr        --pr-id (--comment | --body-file)   github/gitlab only
  list              (--state, --labels, --assignees, --limit optional)
  set-issue-type    --ticket-id --issue-type=NAME      github only
  add-to-project    --ticket-id --project-id=PVT_xxx   github only (echoes item_id)
  set-project-field --item-id --project-id --field-id --option-id   github only
  capabilities      (no args) — returns JSON {supports_version, supports_epic,
                    supports_milestone, supports_epic_auto_close}
  link-parent       --child-id --parent-id (--parent-type=epic|user-story|bug)
  set-milestone     --ticket-id --milestone=NAME
  set-version       --ticket-id --version-name=SEMVER  capability-gated
  list-epics        (no args)
  list-milestones   (no args)                          capability-gated
  list-versions     (no args)                          capability-gated
  close-epic        --ticket-id                        capability-gated

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
  --parent-id=ID                 Platform ID of parent ticket (link-parent / create)
  --parent-type=KIND             epic | user-story | bug (link-parent hint)
  --child-id=ID                  Platform ID of child ticket (link-parent)
  --milestone=NAME               Milestone/Sprint name (set-milestone)
  --version-name=SEMVER          fixVersion/Release name (set-version)
  --story-type=KIND              epic | user-story | task | bug (create)
  --idempotency-check=BOOL       Lookup by title before create (default false)
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
    --parent-id=*)     PARENT_ID="${1#--parent-id=}" ;;
    --parent-type=*)   PARENT_TYPE="${1#--parent-type=}" ;;
    --child-id=*)      CHILD_ID="${1#--child-id=}" ;;
    --milestone=*)     MILESTONE="${1#--milestone=}" ;;
    --version-name=*)  VERSION_NAME="${1#--version-name=}" ;;
    --story-type=*)    STORY_TYPE="${1#--story-type=}" ;;
    --idempotency-check=*) IDEMPOTENCY_CHECK="${1#--idempotency-check=}" ;;
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
  capabilities|link-parent|set-milestone|set-version) ;;
  list-epics|list-milestones|list-versions|close-epic) ;;
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
  github|gitlab|jira|linear) ;;
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

# --- v1.2 capability matrix ---------------------------------------------
# Static per platform. Caller may further degrade based on workspace probe
# (Linear Release configured? GitHub Issue Types enabled?).
capabilities_for() {
  case "$1" in
    github)
      jq -nc '{platform:"github", supports_version:false, supports_epic:true,
               supports_milestone:true, supports_epic_auto_close:false}' ;;
    gitlab)
      jq -nc '{platform:"gitlab", supports_version:true, supports_epic:true,
               supports_milestone:true, supports_epic_auto_close:true}' ;;
    jira)
      jq -nc '{platform:"jira", supports_version:true, supports_epic:true,
               supports_milestone:true, supports_epic_auto_close:true}' ;;
    linear)
      jq -nc '{platform:"linear", supports_version:true, supports_epic:true,
               supports_milestone:true, supports_epic_auto_close:true}' ;;
    *) jq -nc '{ok:false, error:"unknown_platform"}' ;;
  esac
}

# --- v1.2 retry + timeout wrapper ---------------------------------------
# Wraps a CLI invocation. Retries only on transient errors visible in stdout/
# stderr (rate limit, 5xx, 429, timeout). Sleep grows exponentially:
# BACKOFF_MS, 2×BACKOFF_MS, 4×BACKOFF_MS. Each attempt is timed out at
# TIMEOUT_S seconds when `timeout`/`gtimeout` is on PATH.
maybe_timeout() {
  if command -v timeout >/dev/null 2>&1; then
    timeout "$TIMEOUT_S" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$TIMEOUT_S" "$@"
  else
    "$@"
  fi
}

is_transient_err() {
  echo "$1" | grep -qiE '(rate limit|HTTP 5[0-9][0-9]|HTTP 429|429 Too Many|503 Service|temporarily|timed out|deadline exceeded|connection reset)'
}

call_with_retry() {
  local attempt=1 last_out="" last_rc=0
  while [ "$attempt" -le "$RETRY_MAX" ]; do
    last_out=$(maybe_timeout "$@" 2>&1)
    last_rc=$?
    if [ "$last_rc" -eq 0 ]; then
      printf '%s' "$last_out"
      return 0
    fi
    if [ "$attempt" -ge "$RETRY_MAX" ] || ! is_transient_err "$last_out"; then
      printf '%s' "$last_out"
      return "$last_rc"
    fi
    local backoff_ms=$(( BACKOFF_MS * (1 << (attempt - 1)) ))
    sleep "$(awk -v ms="$backoff_ms" 'BEGIN { printf "%.3f", ms / 1000 }')"
    attempt=$(( attempt + 1 ))
  done
  printf '%s' "$last_out"
  return "$last_rc"
}

# --- v1.2 hierarchical strict ------------------------------------------
# Refuses to push a child ticket whose parent has no resolved platform_id.
require_parent_id() {
  if [ -z "$PARENT_ID" ] || [ "$PARENT_ID" = "null" ]; then
    jq -nc '{ok:false, error:"parent_unresolved",
             reason:"refused: child push requires --parent-id with platform_id (decision 7b)"}'
    exit 1
  fi
}

# --- v1.2 idempotence : lookup by title before create -------------------
lookup_existing_by_title() {
  local title="$1" bin out
  case "$PLATFORM" in
    github)
      bin=$(gh_bin); command -v "$bin" >/dev/null 2>&1 || return 1
      out=$(call_with_retry "$bin" issue list --search "in:title \"$title\"" --json number,title,url --limit 5 2>&1) || return 1
      echo "$out" | jq -e --arg t "$title" '[.[] | select(.title == $t)] | .[0]' >/dev/null 2>&1 || return 1
      echo "$out" | jq -c --arg t "$title" '[.[] | select(.title == $t)] | .[0]'
      ;;
    gitlab)
      bin=$(glab_bin); command -v "$bin" >/dev/null 2>&1 || return 1
      out=$(call_with_retry "$bin" issue list --search "$title" --output json --per-page 5 2>&1) || return 1
      echo "$out" | jq -e --arg t "$title" '[.[] | select(.title == $t)] | .[0]' >/dev/null 2>&1 || return 1
      echo "$out" | jq -c --arg t "$title" '[.[] | select(.title == $t) | {platform_id:(.iid|tostring), url:.web_url, title:.title}] | .[0]'
      ;;
    *) return 1 ;;
  esac
}

# --- DRY RUN write shortcut ----------------------------------------------
_is_read_action() {
  case "$1" in
    get|list|list-epics|list-milestones|list-versions|capabilities) return 0 ;;
    *) return 1 ;;
  esac
}

if [ "$DRY_RUN" = "true" ] && ! _is_read_action "$ACTION"; then
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
    --arg parent_id "$PARENT_ID" \
    --arg parent_type "$PARENT_TYPE" \
    --arg child_id "${CHILD_ID:-${TICKET_ID:-DRY-0}}" \
    --arg milestone "$MILESTONE" \
    --arg version_name "$VERSION_NAME" \
    --arg story_type "$STORY_TYPE" \
    --argjson labels    "$(csv_to_array "$LABELS_CSV")" \
    --argjson assignees "$(csv_to_array "$ASSIGNEES_CSV")" '
    {dry_run:true, action:$act, platform_id:$pid, pr_id:$pr_id, title:$title, body:$body, state:$state,
     comment:$comment, labels:$labels, assignees:$assignees,
     issue_type:$issue_type, project_id:$project_id, field_id:$field_id, option_id:$option_id,
     value:$value, item_id:$item_id,
     parent_id:$parent_id, parent_type:$parent_type, child_id:$child_id,
     milestone:$milestone, version_name:$version_name, story_type:$story_type}')
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
    --arg parent_id "$PARENT_ID" \
    --arg parent_type "$PARENT_TYPE" \
    --arg child_id "$CHILD_ID" \
    --arg milestone "$MILESTONE" \
    --arg version_name "$VERSION_NAME" \
    --arg story_type "$STORY_TYPE" \
    --argjson labels    "$(csv_to_array "$LABELS_CSV")" \
    --argjson assignees "$(csv_to_array "$ASSIGNEES_CSV")" '
    {
      ok:false, mode:"mcp", reason:"mcp_required",
      descriptor: {
        platform: $plat, action: $act,
        params: (
          {}
          | if $pid          != "" then .ticket_id    = $pid          else . end
          | if $pr_id        != "" then .pr_id        = $pr_id        else . end
          | if $title        != "" then .title        = $title        else . end
          | if $body         != "" then .body         = $body         else . end
          | if $state        != "" then .state        = $state        else . end
          | if $comment      != "" then .comment      = $comment      else . end
          | if $parent_id    != "" then .parent_id    = $parent_id    else . end
          | if $parent_type  != "" then .parent_type  = $parent_type  else . end
          | if $child_id     != "" then .child_id     = $child_id     else . end
          | if $milestone    != "" then .milestone    = $milestone    else . end
          | if $version_name != "" then .version_name = $version_name else . end
          | if $story_type   != "" then .story_type   = $story_type   else . end
          | if ($labels    | length) > 0 then .labels    = $labels    else . end
          | if ($assignees | length) > 0 then .assignees = $assignees else . end
          | if $act == "list" then .limit = ($limit | tonumber) else . end
        )
      }
    }')
  echo "$result"
  exit 10
}

if [ "$ACTION" = "capabilities" ]; then
  caps=$(capabilities_for "$PLATFORM")
  ok_result "static" "$caps"
  exit 0
fi

if [ "$ACTION" = "comment-pr" ] && { [ "$PLATFORM" = "jira" ] || [ "$PLATFORM" = "linear" ]; }; then
  jq -nc --arg p "$PLATFORM" '{ok:false, error:"not_supported", reason:($p + " platform has no PR concept; use action=comment on the parent ticket instead")}'
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

# v1.2 capability-gated rejections (decision 7b — refuse silently-wrong calls)
case "$ACTION:$PLATFORM" in
  set-version:github|list-versions:github|close-epic:github)
    jq -nc --arg act "$ACTION" --arg p "$PLATFORM" \
      '{ok:false, error:"not_supported",
        reason:($act + " not supported on " + $p + " (see capabilities action)")}'
    exit 1
    ;;
esac

if [ "$MODE" = "mcp" ] || [ "$PLATFORM" = "jira" ] || [ "$PLATFORM" = "linear" ]; then
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
      # v1.2 idempotence guard (decision 7b)
      if [ "$IDEMPOTENCY_CHECK" = "true" ]; then
        local existing; existing=$(lookup_existing_by_title "$TITLE" 2>/dev/null || echo "")
        if [ -n "$existing" ] && [ "$existing" != "null" ]; then
          jq -nc --argjson e "$existing" --arg title "$TITLE" \
            '{platform_id:($e.number|tostring), url:$e.url, title:$title, status:"todo", deduped:true}' \
            | { read -r r; ok_result "cli" "$r"; }
          return 0 2>/dev/null || exit 0
        fi
      fi
      local args=(issue create --title "$TITLE")
      [ -n "$BODY" ]          && args+=(--body "$BODY")
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      [ -n "$ASSIGNEES_CSV" ] && args+=(--assignee "$ASSIGNEES_CSV")
      local out; out=$(call_with_retry "$bin" "${args[@]}" 2>&1) || { err_out "gh create failed: $out"; exit 1; }
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
    link-parent)
      need "$CHILD_ID" "child-id required for link-parent"
      require_parent_id
      local repo_full owner name parent_nid child_nid
      repo_full=$(call_with_retry "$bin" repo view --json nameWithOwner -q .nameWithOwner 2>&1) \
        || { err_out "gh repo view failed: $repo_full"; exit 1; }
      owner="${repo_full%%/*}"; name="${repo_full#*/}"
      local resolve_q='query($o:String!,$n:String!,$p:Int!,$c:Int!){
        repository(owner:$o,name:$n){
          parent: issue(number:$p){ id }
          child:  issue(number:$c){ id }
        }
      }'
      local resolved
      resolved=$(call_with_retry "$bin" api graphql -f query="$resolve_q" \
                  -F o="$owner" -F n="$name" -F p="$PARENT_ID" -F c="$CHILD_ID" 2>&1) \
        || { err_out "gh graphql resolve failed: $resolved"; exit 1; }
      parent_nid=$(echo "$resolved" | jq -r '.data.repository.parent.id // ""')
      child_nid=$(echo "$resolved"  | jq -r '.data.repository.child.id  // ""')
      [ -n "$parent_nid" ] || { err_out "parent #$PARENT_ID not found"; exit 1; }
      [ -n "$child_nid"  ] || { err_out "child  #$CHILD_ID not found";  exit 1; }
      local mut_q='mutation($p:ID!,$c:ID!){
        addSubIssue(input:{issueId:$p, subIssueId:$c}){ issue{ id } subIssue{ id } }
      }'
      local mut_out
      mut_out=$(call_with_retry "$bin" api graphql -f query="$mut_q" \
                -F p="$parent_nid" -F c="$child_nid" 2>&1) \
        || { err_out "gh addSubIssue failed: $mut_out"; exit 1; }
      jq -nc --arg p "$PARENT_ID" --arg c "$CHILD_ID" \
        '{parent_id:$p, child_id:$c, linked:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    set-milestone)
      need "$TICKET_ID" "ticket-id required for set-milestone"
      need "$MILESTONE" "milestone required"
      local out; out=$(call_with_retry "$bin" issue edit "$TICKET_ID" --milestone "$MILESTONE" 2>&1) \
        || { err_out "gh set-milestone failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg m "$MILESTONE" \
        '{platform_id:$pid, milestone:$m, updated:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list-epics)
      local out; out=$(call_with_retry "$bin" issue list --label epic --state open \
                       --json number,url,title --limit 100 2>&1) \
        || { err_out "gh list-epics failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {platform_id:(.number|tostring), url:.url, title:.title}]')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list-milestones)
      local repo_full owner name
      repo_full=$(call_with_retry "$bin" repo view --json nameWithOwner -q .nameWithOwner 2>&1) \
        || { err_out "gh repo view failed: $repo_full"; exit 1; }
      owner="${repo_full%%/*}"; name="${repo_full#*/}"
      local out; out=$(call_with_retry "$bin" api "repos/$owner/$name/milestones?state=open&per_page=100" 2>&1) \
        || { err_out "gh list-milestones failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {id:(.number|tostring), title:.title, due_on:(.due_on // null)}]')
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
      if [ "$IDEMPOTENCY_CHECK" = "true" ]; then
        local existing; existing=$(lookup_existing_by_title "$TITLE" 2>/dev/null || echo "")
        if [ -n "$existing" ] && [ "$existing" != "null" ]; then
          jq -nc --argjson e "$existing" --arg title "$TITLE" \
            '{platform_id:$e.platform_id, url:$e.url, title:$title, status:"todo", deduped:true}' \
            | { read -r r; ok_result "cli" "$r"; }
          return 0 2>/dev/null || exit 0
        fi
      fi
      local args=(issue create --title "$TITLE")
      [ -n "$BODY" ]          && args+=(--description "$BODY")
      [ -n "$LABELS_CSV" ]    && args+=(--label "$LABELS_CSV")
      [ -n "$ASSIGNEES_CSV" ] && args+=(--assignee "$ASSIGNEES_CSV")
      local out; out=$(call_with_retry "$bin" "${args[@]}" 2>&1) || { err_out "glab create failed: $out"; exit 1; }
      local url; url=$(printf '%s\n' "$out" | grep -oE 'https?://[^[:space:]]+' | tail -1)
      local iid="${url##*/}"
      jq -nc --arg url "$url" --arg iid "$iid" --arg title "$TITLE" '
        {platform_id:$iid, url:$url, title:$title, status:"todo"}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    get)
      need "$TICKET_ID" "ticket-id required for get"
      local out; out=$(call_with_retry "$bin" issue view "$TICKET_ID" --output json 2>&1) \
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
    link-parent)
      need "$CHILD_ID" "child-id required for link-parent"
      require_parent_id
      # GitLab : child issue gets `Related to #parent` link via REST API,
      # then milestone-of-epic propagates. Group epics need REST POST to
      # /groups/:id/epics/:epic_iid/issues — keep simple : use `related-to`.
      local out; out=$(call_with_retry "$bin" issue update "$CHILD_ID" \
                       --label "parent:${PARENT_ID}" 2>&1) \
        || { err_out "glab link-parent failed: $out"; exit 1; }
      jq -nc --arg p "$PARENT_ID" --arg c "$CHILD_ID" \
        '{parent_id:$p, child_id:$c, linked:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    set-milestone)
      need "$TICKET_ID" "ticket-id required for set-milestone"
      need "$MILESTONE" "milestone required"
      local out; out=$(call_with_retry "$bin" issue update "$TICKET_ID" --milestone "$MILESTONE" 2>&1) \
        || { err_out "glab set-milestone failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg m "$MILESTONE" \
        '{platform_id:$pid, milestone:$m, updated:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    set-version)
      need "$TICKET_ID" "ticket-id required for set-version"
      need "$VERSION_NAME" "version-name required"
      # GitLab : no native fixVersion on issue ; use label `version:X.Y.Z`.
      local out; out=$(call_with_retry "$bin" issue update "$TICKET_ID" --label "version:${VERSION_NAME}" 2>&1) \
        || { err_out "glab set-version failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" --arg v "$VERSION_NAME" \
        '{platform_id:$pid, version:$v, updated:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list-epics)
      local out; out=$(call_with_retry "$bin" issue list --label epic --output json --per-page 100 2>&1) \
        || { err_out "glab list-epics failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {platform_id:(.iid|tostring), url:.web_url, title:.title}]')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list-milestones)
      local out; out=$(call_with_retry "$bin" api "milestones?state=active&per_page=100" 2>&1) \
        || { err_out "glab list-milestones failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {id:(.id|tostring), title:.title, due_on:(.due_date // null)}]')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    list-versions)
      local out; out=$(call_with_retry "$bin" api releases 2>&1) \
        || { err_out "glab list-versions failed: $out"; exit 1; }
      local norm; norm=$(echo "$out" | jq '[.[] | {tag:.tag_name, name:(.name // .tag_name), released_at:(.released_at // null)}]')
      jq -nc --argjson items "$norm" '{items:$items, count:($items|length)}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
    close-epic)
      need "$TICKET_ID" "ticket-id required for close-epic"
      local out; out=$(call_with_retry "$bin" issue close "$TICKET_ID" 2>&1) \
        || { err_out "glab close-epic failed: $out"; exit 1; }
      jq -nc --arg pid "$TICKET_ID" '{platform_id:$pid, closed:true}' \
        | { read -r r; ok_result "cli" "$r"; }
      ;;
  esac
}

case "$PLATFORM" in
  github) run_github ;;
  gitlab) run_gitlab ;;
esac
