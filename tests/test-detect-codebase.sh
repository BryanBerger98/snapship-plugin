#!/usr/bin/env bash
# Tests for skills/_shared/detect-codebase.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/detect-codebase.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t artysan-detcb-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== detect-codebase.sh tests ==="

# 1. empty dir → greenfield
echo ""
echo "[1] empty dir → greenfield"
DIR=$(setup_dir)
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
[ "$hc" = "false" ] && ok "1.1 empty dir = greenfield" || ko "1.1 got $hc"
trash "$DIR" 2>/dev/null || true

# 2. package.json → codebase
echo ""
echo "[2] package.json → codebase"
DIR=$(setup_dir)
echo '{"name":"x","version":"1.0.0"}' > "${DIR}/package.json"
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
sig=$(echo "$OUT" | jq -r '.signals[]')
[ "$hc" = "true" ] && ok "2.1 package.json detected" || ko "2.1 got $hc"
echo "$sig" | grep -q "package.json" && ok "2.2 signal recorded" || ko "2.2 sig=$sig"
trash "$DIR" 2>/dev/null || true

# 3. pyproject.toml → codebase
echo ""
echo "[3] pyproject.toml"
DIR=$(setup_dir)
echo "[project]" > "${DIR}/pyproject.toml"
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
[ "$hc" = "true" ] && ok "3.1 pyproject detected" || ko "3.1"
trash "$DIR" 2>/dev/null || true

# 4. Cargo.toml → codebase
echo ""
echo "[4] Cargo.toml"
DIR=$(setup_dir)
echo "[package]" > "${DIR}/Cargo.toml"
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
[ "$hc" = "true" ] && ok "4.1 Cargo detected" || ko "4.1"
trash "$DIR" 2>/dev/null || true

# 5. .git only with no source → greenfield
echo ""
echo "[5] .git only, no source files → greenfield"
DIR=$(setup_dir)
( cd "$DIR" || exit; git init -q; git config user.email "test@test"; git config user.name "test"; git commit --allow-empty -m init -q )
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
[ "$hc" = "false" ] && ok "5.1 empty git repo = greenfield" || ko "5.1 got $hc"
trash "$DIR" 2>/dev/null || true

# 6. .git with tracked source → codebase
echo ""
echo "[6] .git + tracked .ts file"
DIR=$(setup_dir)
(
  cd "$DIR" || exit
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  echo "export const x = 1;" > app.ts
  git add app.ts
  git commit -m init -q
)
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
tc=$(echo "$OUT" | jq -r '.tracked_count')
[ "$hc" = "true" ] && ok "6.1 git+source = codebase" || ko "6.1 got $hc"
[ "$tc" -ge 1 ] && ok "6.2 tracked_count ≥ 1 ($tc)" || ko "6.2 tc=$tc"
trash "$DIR" 2>/dev/null || true

# 7. .git with only node_modules tracked → greenfield (ignore filter)
echo ""
echo "[7] only node_modules sources → greenfield (filtered)"
DIR=$(setup_dir)
(
  cd "$DIR" || exit
  git init -q
  git config user.email "test@test"
  git config user.name "test"
  mkdir -p node_modules/foo
  echo "module.exports = 1;" > node_modules/foo/index.js
  git add -f node_modules/foo/index.js
  git commit -m init -q
)
OUT=$(bash "$SCRIPT" --project-root="$DIR")
hc=$(echo "$OUT" | jq -r '.has_codebase')
[ "$hc" = "false" ] && ok "7.1 node_modules-only = greenfield" || ko "7.1 got $hc"
trash "$DIR" 2>/dev/null || true

# 8. no project root → exit 2
echo ""
echo "[8] missing dir"
if bash "$SCRIPT" --project-root=/nonexistent/path/xyz >/dev/null 2>&1; then
  ko "8.1 should have rejected missing dir"
else
  ok "8.1 rejected missing dir"
fi

# 9. unknown arg
echo ""
echo "[9] unknown arg"
if bash "$SCRIPT" --bogus >/dev/null 2>&1; then
  ko "9.1 should have rejected --bogus"
else
  ok "9.1 rejected unknown arg"
fi

# 10. JSON well-formed always
echo ""
echo "[10] JSON well-formed"
DIR=$(setup_dir)
OUT=$(bash "$SCRIPT" --project-root="$DIR")
echo "$OUT" | jq empty 2>/dev/null && ok "10.1 stdout is valid JSON" || ko "10.1"
trash "$DIR" 2>/dev/null || true

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
