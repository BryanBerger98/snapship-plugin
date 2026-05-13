#!/usr/bin/env bash
# Tests for skills/_shared/setup-config.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/setup-config.sh"
SCHEMA="${ROOT}/skills/_shared/schemas/config.schema.json"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

unset SNAP_MCP_AVAILABLE 2>/dev/null || true

mk_repo() {
  local dir="$1" url="$2"
  mkdir -p "$dir/.git"
  cat > "$dir/.git/config" <<EOF
[remote "origin"]
	url = $url
	fetch = +refs/heads/*:refs/remotes/origin/*
EOF
}

echo "=== setup-config.sh tests ==="

# 1. detect: github SSH remote
echo ""
echo "[1] detect github SSH"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:owner/repo.git"
out=$(bash "$SCRIPT" --detect --project-root="$TMP" --available=affine,frame0)
[ "$(echo "$out" | jq -r '.repository.platform')" = "github" ] && ok "1.1 platform" || ko "1.1"
[ "$(echo "$out" | jq -r '.repository.http_url')" = "https://github.com/owner/repo" ] && ok "1.2 http_url" || ko "1.2 got $(echo "$out" | jq -r '.repository.http_url')"
[ "$(echo "$out" | jq -r '.repository.ssh_url')" = "git@github.com:owner/repo.git" ] && ok "1.3 ssh_url" || ko "1.3"
[ "$(echo "$out" | jq -r '.tickets.platform')" = "github" ] && ok "1.4 tickets default github" || ko "1.4"
[ "$(echo "$out" | jq -r '.documentation.platform')" = "affine" ] && ok "1.5 affine MCP" || ko "1.5"
[ "$(echo "$out" | jq -r '.wireframes.platform')" = "frame0" ] && ok "1.6 frame0" || ko "1.6"
[ "$(echo "$out" | jq -r '.defaults.lang')" = "fr" ] && ok "1.7 lang default" || ko "1.7"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 2. detect: gitlab HTTPS remote
echo ""
echo "[2] detect gitlab HTTPS"
TMP=$(mktemp -d)
mk_repo "$TMP" "https://gitlab.com/group/proj.git"
out=$(bash "$SCRIPT" --detect --project-root="$TMP")
[ "$(echo "$out" | jq -r '.repository.platform')" = "gitlab" ] && ok "2.1 gitlab" || ko "2.1"
[ "$(echo "$out" | jq -r '.repository.http_url')" = "https://gitlab.com/group/proj" ] && ok "2.2 http stripped .git" || ko "2.2"
echo "$out" | jq -e '.repository | has("ssh_url") | not' >/dev/null && ok "2.3 no ssh on https" || ko "2.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 3. detect: docs prefer affine over notion
echo ""
echo "[3] detect docs preference"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
out=$(bash "$SCRIPT" --detect --project-root="$TMP" --available=affine,notion)
[ "$(echo "$out" | jq -r '.documentation.platform')" = "affine" ] && ok "3.1 affine wins" || ko "3.1"
out=$(bash "$SCRIPT" --detect --project-root="$TMP" --available=notion)
[ "$(echo "$out" | jq -r '.documentation.platform')" = "notion" ] && ok "3.2 notion fallback" || ko "3.2"
out=$(bash "$SCRIPT" --detect --project-root="$TMP" --available=)
echo "$out" | jq -e '.documentation | has("platform") | not' >/dev/null && ok "3.3 no docs MCP → empty" || ko "3.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 4. detect: no .git → empty repository
echo ""
echo "[4] detect no git"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --detect --project-root="$TMP")
echo "$out" | jq -e '.repository | has("platform") | not' >/dev/null && ok "4.1 no platform" || ko "4.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 5. write: file created
echo ""
echo "[5] write basic"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
out=$(bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true)
[ -f "$TMP/snapship.config.json" ] && ok "5.1 file exists" || ko "5.1"
[ "$out" = "$TMP/snapship.config.json" ] && ok "5.2 stdout = path" || ko "5.2"
v=$(jq -r '.version' "$TMP/snapship.config.json")
[ "$v" = "1.0" ] && ok "5.3 version 1.0" || ko "5.3 got $v"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 6. write: refuse overwrite
echo ""
echo "[6] write no overwrite"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
echo '{}' > "$TMP/snapship.config.json"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true >/dev/null 2>&1
rc=$?
[ $rc -eq 2 ] && ok "6.1 exit 2 on existing" || ko "6.1 exit $rc"
[ "$(cat "$TMP/snapship.config.json")" = "{}" ] && ok "6.2 file untouched" || ko "6.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 7. write --force overwrites
echo ""
echo "[7] write --force"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
echo '{}' > "$TMP/snapship.config.json"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true --force >/dev/null
v=$(jq -r '.version' "$TMP/snapship.config.json")
[ "$v" = "1.0" ] && ok "7.1 force overwrite" || ko "7.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 8. write: explicit flags override detected
echo ""
echo "[8] flags override"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --tickets-platform=jira --lang=en >/dev/null
[ "$(jq -r '.tickets.platform' "$TMP/snapship.config.json")" = "jira" ] && ok "8.1 tickets jira" || ko "8.1"
[ "$(jq -r '.defaults.lang' "$TMP/snapship.config.json")" = "en" ] && ok "8.2 lang en" || ko "8.2"
[ "$(jq -r '.repository.platform' "$TMP/snapship.config.json")" = "github" ] && ok "8.3 repo unchanged" || ko "8.3"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 9. write: --from-answers merged
echo ""
echo "[9] from-answers merge"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --from-answers='{"ai":{"max_parallel_agents":3}}' >/dev/null
[ "$(jq -r '.ai.max_parallel_agents' "$TMP/snapship.config.json")" = "3" ] && ok "9.1 nested merged" || ko "9.1"
[ "$(jq -r '.repository.platform' "$TMP/snapship.config.json")" = "github" ] && ok "9.2 base preserved" || ko "9.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 10. auto-mode requires resolved fields
echo ""
echo "[10] auto-mode unresolved"
TMP=$(mktemp -d)
# no .git/config, no MCPs
bash "$SCRIPT" --write --project-root="$TMP" --available= --auto-mode=true >/dev/null 2>&1
rc=$?
[ $rc -eq 1 ] && ok "10.1 unresolved fails" || ko "10.1 exit $rc"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 11. auto-mode resolved via flags
echo ""
echo "[11] auto-mode resolved via flags"
TMP=$(mktemp -d)
bash "$SCRIPT" --write --project-root="$TMP" --available= --auto-mode=true \
  --repository-platform=github --tickets-platform=github --docs-platform=affine >/dev/null
[ -f "$TMP/snapship.config.json" ] && ok "11.1 written" || ko "11.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 12. Generated config validates against schema (when ajv-cli available)
echo ""
echo "[12] schema validation"
if command -v ajv >/dev/null 2>&1; then
  TMP=$(mktemp -d)
  mk_repo "$TMP" "git@github.com:o/r.git"
  bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true >/dev/null
  if ajv validate --spec=draft2020 --strict=false -s "$SCHEMA" -d "$TMP/snapship.config.json" >/dev/null 2>&1; then
    ok "12.1 validates against schema"
  else
    ko "12.1 schema validation failed"
  fi
  trash "$TMP" 2>/dev/null || rm -rf "$TMP"
else
  echo "  SKIP  12.1 ajv-cli not installed"
fi

# 13. Invalid --from-answers JSON
echo ""
echo "[13] bad answers JSON"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --from-answers='not json' >/dev/null 2>&1
[ $? -eq 1 ] && ok "13.1 invalid JSON rejected" || ko "13.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13b. design.extract opt-in
echo ""
echo "[13b] design.extract opt-in"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --design-platform=figma --design-extract-opt-in=true >/dev/null
echo "$(jq -r '.design.extract | type' "$TMP/snapship.config.json")" | grep -q object && ok "13b.1 design.extract object" || ko "13b.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13c. design.extract NOT written if opt-in=false and no granular flag
echo ""
echo "[13c] no design.extract by default"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --design-platform=figma >/dev/null
jq -e '.design | has("extract") | not' "$TMP/snapship.config.json" >/dev/null && ok "13c.1 no extract block" || ko "13c.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13d. design.extract granular flags
echo ""
echo "[13d] design.extract granular flags"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --design-platform=figma \
  --design-extract-source=app/components \
  --design-extract-out=ds/specs >/dev/null
[ "$(jq -r '.design.extract.source' "$TMP/snapship.config.json")" = "app/components" ] && ok "13d.1 source" || ko "13d.1"
[ "$(jq -r '.design.extract.out' "$TMP/snapship.config.json")" = "ds/specs" ] && ok "13d.2 out" || ko "13d.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13e. invalid opt-in value rejected
echo ""
echo "[13e] design-extract-opt-in bad value"
TMP=$(mktemp -d)
mk_repo "$TMP" "git@github.com:o/r.git"
bash "$SCRIPT" --write --project-root="$TMP" --available=affine,frame0 --auto-mode=true \
  --design-extract-opt-in=maybe >/dev/null 2>&1
[ $? -eq 1 ] && ok "13e.1 rejected" || ko "13e.1"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 14. Output is valid JSON
echo ""
echo "[14] detect output valid JSON"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --detect --project-root="$TMP")
echo "$out" | jq empty 2>/dev/null && ok "14.1 valid" || ko "14.1: $out"
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
