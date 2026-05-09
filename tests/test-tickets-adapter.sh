#!/usr/bin/env bash
# Tests for skills/_shared/tickets-adapter.sh
#
# Mocks `gh` and `glab` via $ARTYSAN_GH_BIN / $ARTYSAN_GLAB_BIN test hooks,
# pointing each to a stub script under a temp dir.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

# Stub `gh` binary that prints fixed responses based on first 2 args.
mk_gh_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
# arg0 = issue, arg1 = subcommand
case "${1:-}-${2:-}" in
  issue-create)
    echo "https://github.com/o/r/issues/42"
    ;;
  issue-view)
    cat <<'JSON'
{"number":42,"url":"https://github.com/o/r/issues/42","title":"T","body":"B","state":"OPEN","labels":[{"name":"bug"}],"assignees":[{"login":"alice"}]}
JSON
    ;;
  issue-edit)
    echo "https://github.com/o/r/issues/42"
    ;;
  issue-comment)
    echo "https://github.com/o/r/issues/42#issuecomment-1"
    ;;
  issue-close|issue-reopen)
    echo "ok"
    ;;
  issue-list)
    cat <<'JSON'
[{"number":1,"url":"https://github.com/o/r/issues/1","title":"a","body":"","state":"OPEN","labels":[{"name":"x"}],"assignees":[]},
 {"number":2,"url":"https://github.com/o/r/issues/2","title":"b","body":"","state":"CLOSED","labels":[],"assignees":[{"login":"bob"}]}]
JSON
    ;;
  *) echo "stub: unknown gh args: $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$path"
}

mk_glab_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
case "${1:-}-${2:-}" in
  issue-create)
    echo "Creating issue..."
    echo "https://gitlab.com/o/r/-/issues/7"
    ;;
  issue-view)
    cat <<'JSON'
{"iid":7,"web_url":"https://gitlab.com/o/r/-/issues/7","title":"T","description":"D","state":"opened","labels":["bug"],"assignees":[{"username":"alice"}]}
JSON
    ;;
  issue-update)
    echo "updated"
    ;;
  issue-note)
    echo "noted"
    ;;
  issue-close|issue-reopen)
    echo "ok"
    ;;
  issue-list)
    cat <<'JSON'
[{"iid":1,"web_url":"https://gitlab.com/o/r/-/issues/1","title":"a","description":"","state":"opened","labels":[],"assignees":[]},
 {"iid":2,"web_url":"https://gitlab.com/o/r/-/issues/2","title":"b","description":"","state":"closed","labels":["bug"],"assignees":[{"username":"bob"}]}]
JSON
    ;;
  *) echo "stub: unknown glab args: $*" >&2; exit 1 ;;
esac
STUB
  chmod +x "$path"
}

mk_failing_stub() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
echo "boom" >&2
exit 1
STUB
  chmod +x "$path"
}

unset ARTYSAN_DRY_RUN ARTYSAN_GH_BIN ARTYSAN_GLAB_BIN ARTYSAN_PROJECT_ROOT 2>/dev/null || true

echo "=== tickets-adapter.sh tests ==="

# --- arg validation -------------------------------------------------------

echo ""
echo "[1] help exits 0"
bash "$SCRIPT" --help >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1 --help exit 0" || ko "1.1"

echo ""
echo "[2] missing --action"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "2.1 exit 2" || ko "2.1"

echo ""
echo "[3] bad action"
bash "$SCRIPT" --action=foo --platform=github >/dev/null 2>&1
[ $? -eq 2 ] && ok "3.1 exit 2" || ko "3.1"

echo ""
echo "[4] bad mode"
bash "$SCRIPT" --action=get --platform=github --ticket-id=1 --mode=zzz >/dev/null 2>&1
[ $? -eq 2 ] && ok "4.1 exit 2" || ko "4.1"

echo ""
echo "[5] missing platform (no config)"
TMP=$(mktemp -d)
bash "$SCRIPT" --action=list --project-root="$TMP" >/dev/null 2>&1
[ $? -eq 2 ] && ok "5.1 exit 2" || ko "5.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[6] bad platform"
bash "$SCRIPT" --action=list --platform=bitbucket >/dev/null 2>&1
[ $? -eq 2 ] && ok "6.1 exit 2" || ko "6.1"

# --- dry-run --------------------------------------------------------------

echo ""
echo "[7] dry-run create github"
out=$(bash "$SCRIPT" --action=create --platform=github --title="hi" --body="b" --labels="x,y" --dry-run)
rc=$?
[ $rc -eq 0 ] && ok "7.1 exit 0" || ko "7.1 exit $rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ]                        && ok "7.2 ok"           || ko "7.2"
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ]                   && ok "7.3 mode dry-run" || ko "7.3"
[ "$(echo "$out" | jq -r '.action')" = "create" ]                  && ok "7.4 action"       || ko "7.4"
[ "$(echo "$out" | jq -r '.platform')" = "github" ]                && ok "7.5 platform"     || ko "7.5"
[ "$(echo "$out" | jq -r '.result.title')" = "hi" ]                && ok "7.6 title"        || ko "7.6"
[ "$(echo "$out" | jq -r '.result.labels | length')" = "2" ]       && ok "7.7 labels"       || ko "7.7"

echo ""
echo "[8] dry-run via env var"
out=$(ARTYSAN_DRY_RUN=true bash "$SCRIPT" --action=update --platform=gitlab --ticket-id=1 --title="x")
[ "$(echo "$out" | jq -r '.mode')" = "dry-run" ] && ok "8.1 env triggers dry-run" || ko "8.1"

echo ""
echo "[9] dry-run NOT applied to read actions (should hit CLI)"
TMP=$(mktemp -d)
mk_failing_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=get --platform=github --ticket-id=1 --dry-run 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "9.1 read actions skip dry-run shortcut" || ko "9.1 rc=$rc"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- MCP descriptor (jira) -----------------------------------------------

echo ""
echo "[10] jira → MCP descriptor"
out=$(bash "$SCRIPT" --action=create --platform=jira --title="t" --body="b" --labels="a,b")
rc=$?
[ $rc -eq 10 ] && ok "10.1 exit 10" || ko "10.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "false" ]                              && ok "10.2 ok=false"           || ko "10.2"
[ "$(echo "$out" | jq -r '.mode')" = "mcp" ]                              && ok "10.3 mode mcp"           || ko "10.3"
[ "$(echo "$out" | jq -r '.reason')" = "mcp_required" ]                   && ok "10.4 reason"             || ko "10.4"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "jira" ]              && ok "10.5 desc.platform"      || ko "10.5"
[ "$(echo "$out" | jq -r '.descriptor.action')" = "create" ]              && ok "10.6 desc.action"        || ko "10.6"
[ "$(echo "$out" | jq -r '.descriptor.params.title')" = "t" ]             && ok "10.7 desc.params.title"  || ko "10.7"
[ "$(echo "$out" | jq -r '.descriptor.params.labels | length')" = "2" ]   && ok "10.8 desc.params.labels" || ko "10.8"

echo ""
echo "[11] --mode=mcp forces descriptor on github"
out=$(bash "$SCRIPT" --action=get --platform=github --ticket-id=42 --mode=mcp)
rc=$?
[ $rc -eq 10 ] && ok "11.1 exit 10" || ko "11.1"
[ "$(echo "$out" | jq -r '.descriptor.action')" = "get" ]      && ok "11.2 action"    || ko "11.2"
[ "$(echo "$out" | jq -r '.descriptor.params.ticket_id')" = "42" ] && ok "11.3 ticket_id" || ko "11.3"

echo ""
echo "[12] jira list includes limit"
out=$(bash "$SCRIPT" --action=list --platform=jira --limit=10)
[ "$(echo "$out" | jq -r '.descriptor.params.limit')" = "10" ] && ok "12.1 limit numeric" || ko "12.1"

# --- GitHub CLI -----------------------------------------------------------

echo ""
echo "[13] github create via mock gh"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=create --platform=github --title="T")
rc=$?
[ $rc -eq 0 ] && ok "13.1 exit 0" || ko "13.1 rc=$rc"
[ "$(echo "$out" | jq -r '.mode')" = "cli" ]                                   && ok "13.2 mode cli"     || ko "13.2"
[ "$(echo "$out" | jq -r '.result.platform_id')" = "42" ]                      && ok "13.3 platform_id"  || ko "13.3"
[ "$(echo "$out" | jq -r '.result.url')" = "https://github.com/o/r/issues/42" ] && ok "13.4 url"          || ko "13.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[14] github get normalizes fields"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=get --platform=github --ticket-id=42)
[ "$(echo "$out" | jq -r '.result.platform_id')" = "42" ]      && ok "14.1 id"     || ko "14.1"
[ "$(echo "$out" | jq -r '.result.title')" = "T" ]             && ok "14.2 title"  || ko "14.2"
[ "$(echo "$out" | jq -r '.result.status')" = "todo" ]         && ok "14.3 status" || ko "14.3"
[ "$(echo "$out" | jq -r '.result.labels[0]')" = "bug" ]       && ok "14.4 labels" || ko "14.4"
[ "$(echo "$out" | jq -r '.result.assignees[0]')" = "alice" ]  && ok "14.5 assig"  || ko "14.5"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[15] github list returns items"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=list --platform=github --limit=5)
[ "$(echo "$out" | jq -r '.result.count')" = "2" ]                 && ok "15.1 count"   || ko "15.1"
[ "$(echo "$out" | jq -r '.result.items[1].status')" = "done" ]    && ok "15.2 closed→done" || ko "15.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[16] github update returns updated:true"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=update --platform=github --ticket-id=42 --title="new")
[ "$(echo "$out" | jq -r '.result.updated')" = "true" ] && ok "16.1 updated" || ko "16.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[17] github comment"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=comment --platform=github --ticket-id=42 --comment="hi")
[ "$(echo "$out" | jq -r '.result.platform_id')" = "42" ]                                && ok "17.1 id"  || ko "17.1"
[ "$(echo "$out" | jq -r '.result.comment_url')" != "" ]                                 && ok "17.2 url" || ko "17.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[18] github comment requires --comment"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=comment --platform=github --ticket-id=42 >/dev/null 2>&1
[ $? -eq 2 ] && ok "18.1 missing comment exit 2" || ko "18.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[19] github CLI failure → ok:false exit 1"
TMP=$(mktemp -d)
mk_failing_stub "$TMP/gh"
out=$(ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=get --platform=github --ticket-id=1 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "19.1 exit 1" || ko "19.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok' 2>/dev/null)" = "false" ] && ok "19.2 ok=false" || ko "19.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[20] gh CLI not installed"
out=$(ARTYSAN_GH_BIN="/nonexistent/gh-binary" bash "$SCRIPT" --action=get --platform=github --ticket-id=1 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "20.1 exit 1" || ko "20.1 rc=$rc"

# --- GitLab CLI -----------------------------------------------------------

echo ""
echo "[21] gitlab create via mock glab"
TMP=$(mktemp -d)
mk_glab_stub "$TMP/glab"
out=$(ARTYSAN_GLAB_BIN="$TMP/glab" bash "$SCRIPT" --action=create --platform=gitlab --title="T" --body="d")
rc=$?
[ $rc -eq 0 ] && ok "21.1 exit 0" || ko "21.1 rc=$rc"
[ "$(echo "$out" | jq -r '.result.platform_id')" = "7" ]                                  && ok "21.2 iid"     || ko "21.2"
[ "$(echo "$out" | jq -r '.result.url')" = "https://gitlab.com/o/r/-/issues/7" ]          && ok "21.3 url"     || ko "21.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[22] gitlab get normalizes"
TMP=$(mktemp -d)
mk_glab_stub "$TMP/glab"
out=$(ARTYSAN_GLAB_BIN="$TMP/glab" bash "$SCRIPT" --action=get --platform=gitlab --ticket-id=7)
[ "$(echo "$out" | jq -r '.result.platform_id')" = "7" ]                && ok "22.1 id"        || ko "22.1"
[ "$(echo "$out" | jq -r '.result.status')" = "todo" ]                  && ok "22.2 opened→todo" || ko "22.2"
[ "$(echo "$out" | jq -r '.result.labels[0]')" = "bug" ]                && ok "22.3 labels"    || ko "22.3"
[ "$(echo "$out" | jq -r '.result.assignees[0]')" = "alice" ]           && ok "22.4 assignee"  || ko "22.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[23] gitlab list"
TMP=$(mktemp -d)
mk_glab_stub "$TMP/glab"
out=$(ARTYSAN_GLAB_BIN="$TMP/glab" bash "$SCRIPT" --action=list --platform=gitlab)
[ "$(echo "$out" | jq -r '.result.count')" = "2" ]                  && ok "23.1 count"     || ko "23.1"
[ "$(echo "$out" | jq -r '.result.items[1].status')" = "done" ]     && ok "23.2 closed→done" || ko "23.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[24] gitlab update"
TMP=$(mktemp -d)
mk_glab_stub "$TMP/glab"
out=$(ARTYSAN_GLAB_BIN="$TMP/glab" bash "$SCRIPT" --action=update --platform=gitlab --ticket-id=7 --title="new")
[ "$(echo "$out" | jq -r '.result.updated')" = "true" ] && ok "24.1 updated" || ko "24.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[25] gitlab comment"
TMP=$(mktemp -d)
mk_glab_stub "$TMP/glab"
out=$(ARTYSAN_GLAB_BIN="$TMP/glab" bash "$SCRIPT" --action=comment --platform=gitlab --ticket-id=7 --comment="hi")
[ "$(echo "$out" | jq -r '.result.comment')" = "true" ] && ok "25.1 comment ok" || ko "25.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- platform from config -------------------------------------------------

echo ""
echo "[26] platform resolved from config.tickets.platform"
TMP=$(mktemp -d)
cat > "$TMP/artysan.config.json" <<'JSON'
{
  "$schema": "./skills/_shared/schemas/config.schema.json",
  "version": "1.0",
  "tickets": { "platform": "jira" }
}
JSON
out=$(bash "$SCRIPT" --action=create --title="x" --project-root="$TMP")
rc=$?
[ $rc -eq 10 ] && ok "26.1 jira from config → exit 10" || ko "26.1 rc=$rc"
[ "$(echo "$out" | jq -r '.descriptor.platform')" = "jira" ] && ok "26.2 platform jira" || ko "26.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- create requires title ------------------------------------------------

echo ""
echo "[27] github create without title fails"
TMP=$(mktemp -d)
mk_gh_stub "$TMP/gh"
ARTYSAN_GH_BIN="$TMP/gh" bash "$SCRIPT" --action=create --platform=github >/dev/null 2>&1
[ $? -eq 2 ] && ok "27.1 missing title exit 2" || ko "27.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[28] update requires --ticket-id"
bash "$SCRIPT" --action=update --platform=github --title="x" >/dev/null 2>&1
[ $? -eq 2 ] && ok "28.1 missing ticket-id exit 2" || ko "28.1"

unset TMP

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"

if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "Errors:"
  printf '  - %s\n' "${ERRORS[@]}"
  exit 1
fi
