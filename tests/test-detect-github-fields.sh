#!/usr/bin/env bash
# Tests for skills/_shared/detect-github-fields.sh
# Stubs `gh` via $SNAP_GH_BIN. The stub answers to:
#   - repo view --json nameWithOwner -q .nameWithOwner   → "<OWNER>/<NAME>"
#   - api graphql -f query=... -F owner=... -F name=...  → branches by query body
#
# The stub picks its response by inspecting the query string (Issue Types vs
# Projects v2) so a single binary can satisfy both round-trips.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/detect-github-fields.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

# Stub `gh` that returns canned GraphQL responses.
mk_gh_full() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
# arg parsing: pass-through; we route by inspecting the joined args.
ARGS="$*"
case "$ARGS" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "acme/widgets"
    exit 0
    ;;
esac
# api graphql case — read the query and branch
if echo "$ARGS" | grep -q "issueTypes(first:50)"; then
  cat <<'JSON'
{
  "data": {
    "repository": {
      "owner": { "__typename": "Organization", "login": "acme" },
      "issueTypes": {
        "nodes": [
          {"id":"IT_A","name":"Feature","description":""},
          {"id":"IT_B","name":"Bug","description":""},
          {"id":"IT_C","name":"Epic","description":"Big work"}
        ]
      }
    }
  }
}
JSON
  exit 0
fi
if echo "$ARGS" | grep -q "projectsV2(first:20)"; then
  cat <<'JSON'
{
  "data": {
    "repository": {
      "projectsV2": {
        "nodes": [
          {
            "id": "PVT_1", "number": 12, "title": "Widgets Roadmap",
            "url": "https://github.com/orgs/acme/projects/12",
            "fields": {
              "nodes": [
                {"__typename":"ProjectV2Field","id":"PVTF_T","name":"Title","dataType":"TITLE"},
                {"__typename":"ProjectV2SingleSelectField","id":"PVTSSF_P","name":"Priority","dataType":"SINGLE_SELECT",
                 "options":[{"id":"opt_p0","name":"P0"},{"id":"opt_p1","name":"P1"}]},
                {"__typename":"ProjectV2SingleSelectField","id":"PVTSSF_S","name":"Size","dataType":"SINGLE_SELECT",
                 "options":[{"id":"opt_s","name":"S"},{"id":"opt_m","name":"M"}]}
              ]
            }
          }
        ]
      }
    }
  }
}
JSON
  exit 0
fi
echo "stub: unhandled gh args: $ARGS" >&2
exit 1
STUB
  chmod +x "$path"
}

# Stub that succeeds on repo view + projects, but fails on issueTypes
# (simulates org without the Issue Types feature).
mk_gh_no_issue_types() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
ARGS="$*"
case "$ARGS" in
  "repo view --json nameWithOwner -q .nameWithOwner")
    echo "user/repo"
    exit 0
    ;;
esac
if echo "$ARGS" | grep -q "issueTypes(first:50)"; then
  echo "GraphQL: Field 'issueTypes' doesn't exist on type 'Repository'" >&2
  exit 1
fi
if echo "$ARGS" | grep -q "projectsV2(first:20)"; then
  cat <<'JSON'
{"data":{"repository":{"projectsV2":{"nodes":[]}}}}
JSON
  exit 0
fi
exit 1
STUB
  chmod +x "$path"
}

# Stub that fails on repo view (no current repo)
mk_gh_no_repo() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path" <<'STUB'
#!/usr/bin/env bash
echo "no repo" >&2
exit 1
STUB
  chmod +x "$path"
}

unset SNAP_GH_BIN 2>/dev/null || true

echo "=== detect-github-fields.sh tests ==="

# --- arg validation -------------------------------------------------------

echo ""
echo "[1] help exits 0"
bash "$SCRIPT" --help >/dev/null 2>&1
[ $? -eq 0 ] && ok "1.1 --help exit 0" || ko "1.1"

echo ""
echo "[2] unknown arg → exit 2"
bash "$SCRIPT" --bogus 2>/dev/null
[ $? -eq 2 ] && ok "2.1 exit 2" || ko "2.1"

# --- gh missing -----------------------------------------------------------

echo ""
echo "[3] gh binary absent"
out=$(SNAP_GH_BIN="/nonexistent/gh-binary" bash "$SCRIPT" --repo=foo/bar 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "3.1 exit 1" || ko "3.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok' 2>/dev/null)" = "false" ] && ok "3.2 ok:false" || ko "3.2"
[ "$(echo "$out" | jq -r '.error' 2>/dev/null)" = "gh CLI not installed" ] && ok "3.3 error msg" || ko "3.3"

# --- repo resolution ------------------------------------------------------

echo ""
echo "[4] no --repo, gh repo view fails → error"
TMP=$(mktemp -d)
mk_gh_no_repo "$TMP/gh"
out=$(SNAP_GH_BIN="$TMP/gh" bash "$SCRIPT" 2>&1)
rc=$?
[ $rc -eq 1 ] && ok "4.1 exit 1" || ko "4.1 rc=$rc"
echo "$out" | jq -e '.error | contains("could not resolve")' >/dev/null 2>&1 \
  && ok "4.2 error mentions resolve" || ko "4.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

echo ""
echo "[5] bad --repo format"
out=$(bash "$SCRIPT" --repo=invalidformat 2>&1 || true)
echo "$out" | jq -e '.error | contains("invalid --repo")' >/dev/null 2>&1 \
  && ok "5.1 invalid format" || ko "5.1 got: $out"

# --- happy path -----------------------------------------------------------

echo ""
echo "[6] happy path — issue types + projects detected"
TMP=$(mktemp -d)
mk_gh_full "$TMP/gh"
out=$(SNAP_GH_BIN="$TMP/gh" bash "$SCRIPT")
rc=$?
[ $rc -eq 0 ] && ok "6.1 exit 0" || ko "6.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "6.2 ok=true" || ko "6.2"
[ "$(echo "$out" | jq -r '.owner')" = "acme" ] && ok "6.3 owner" || ko "6.3"
[ "$(echo "$out" | jq -r '.repo')" = "widgets" ] && ok "6.4 repo" || ko "6.4"
[ "$(echo "$out" | jq -r '.owner_type')" = "Organization" ] && ok "6.5 owner_type" || ko "6.5"
[ "$(echo "$out" | jq -r '.issue_types | length')" = "3" ] && ok "6.6 3 issue types" || ko "6.6"
echo "$out" | jq -e '.issue_types | any(.name=="Feature")' >/dev/null && ok "6.7 Feature present" || ko "6.7"
echo "$out" | jq -e '.issue_types | any(.name=="Bug")'     >/dev/null && ok "6.8 Bug present" || ko "6.8"
echo "$out" | jq -e '.issue_types | any(.name=="Epic")'    >/dev/null && ok "6.9 Epic present" || ko "6.9"
[ "$(echo "$out" | jq -r '.projects | length')" = "1" ] && ok "6.10 1 project" || ko "6.10"
[ "$(echo "$out" | jq -r '.projects[0].id')" = "PVT_1" ] && ok "6.11 project.id" || ko "6.11"
[ "$(echo "$out" | jq -r '.projects[0].number')" = "12" ] && ok "6.12 project.number" || ko "6.12"
[ "$(echo "$out" | jq -r '.projects[0].fields | length')" = "3" ] && ok "6.13 3 fields" || ko "6.13"
# single-select keeps options; title field still listed but no options
echo "$out" | jq -e '.projects[0].fields[] | select(.name=="Priority") | .options | length == 2' >/dev/null \
  && ok "6.14 Priority has 2 options" || ko "6.14"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- graceful fallback ----------------------------------------------------

echo ""
echo "[7] Issue Types not supported → empty array, no fatal"
TMP=$(mktemp -d)
mk_gh_no_issue_types "$TMP/gh"
out=$(SNAP_GH_BIN="$TMP/gh" bash "$SCRIPT")
rc=$?
[ $rc -eq 0 ] && ok "7.1 exit 0 (graceful)" || ko "7.1 rc=$rc"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "7.2 ok=true" || ko "7.2"
[ "$(echo "$out" | jq -r '.issue_types | length')" = "0" ] && ok "7.3 0 issue types" || ko "7.3"
[ "$(echo "$out" | jq -r '.projects | length')" = "0" ] && ok "7.4 0 projects" || ko "7.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# --- accepts --project-root parity arg ------------------------------------

echo ""
echo "[8] --project-root accepted silently"
TMP=$(mktemp -d)
mk_gh_full "$TMP/gh"
out=$(SNAP_GH_BIN="$TMP/gh" bash "$SCRIPT" --project-root="$TMP" --repo=acme/widgets)
rc=$?
[ $rc -eq 0 ] && ok "8.1 exit 0" || ko "8.1"
[ "$(echo "$out" | jq -r '.ok')" = "true" ] && ok "8.2 ok=true" || ko "8.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

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
