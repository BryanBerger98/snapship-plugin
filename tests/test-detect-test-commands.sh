#!/usr/bin/env bash
# Tests for skills/_shared/detect-test-commands.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/detect-test-commands.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

cleanup() {
  [ -n "${TMP:-}" ] && [ -d "$TMP" ] && { trash "$TMP" 2>/dev/null || rm -rf "$TMP"; }
}
trap cleanup EXIT

echo "=== detect-test-commands.sh tests ==="

# 1. Empty project → empty JSON
echo ""
echo "[1] empty project"
TMP=$(mktemp -d)
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$out" = "{}" ] && ok "1.1 empty JSON" || ko "1.1 got '$out'"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 2. package.json with all scripts (npm)
echo ""
echo "[2] npm full"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{
  "name": "x",
  "scripts": {
    "test": "vitest",
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "format": "prettier -w ."
  }
}
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "npm run test" ] && ok "2.1 test" || ko "2.1 test = $(echo "$out" | jq -r '.test_command')"
[ "$(echo "$out" | jq -r '.typecheck_command')" = "npm run typecheck" ] && ok "2.2 typecheck" || ko "2.2 got $(echo "$out" | jq -r '.typecheck_command')"
[ "$(echo "$out" | jq -r '.lint_command')" = "npm run lint" ] && ok "2.3 lint" || ko "2.3"
[ "$(echo "$out" | jq -r '.format_command')" = "npm run format" ] && ok "2.4 format" || ko "2.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 3. pnpm detection
echo ""
echo "[3] pnpm via lockfile"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
touch "$TMP/pnpm-lock.yaml"
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "pnpm run test" ] && ok "3.1 pnpm" || ko "3.1 got $(echo "$out" | jq -r '.test_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 4. yarn detection
echo ""
echo "[4] yarn via lockfile"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
touch "$TMP/yarn.lock"
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "yarn test" ] && ok "4.1 yarn" || ko "4.1 got $(echo "$out" | jq -r '.test_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 5. bun detection
echo ""
echo "[5] bun via lockfile"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
touch "$TMP/bun.lockb"
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "bun run test" ] && ok "5.1 bun" || ko "5.1 got $(echo "$out" | jq -r '.test_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 6. typecheck alias type-check
echo ""
echo "[6] typecheck alias"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "type-check": "tsc --noEmit" } }
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.typecheck_command')" = "npm run type-check" ] && ok "6.1 type-check fallback" || ko "6.1 got $(echo "$out" | jq -r '.typecheck_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 7. Cargo
echo ""
echo "[7] Cargo.toml"
TMP=$(mktemp -d)
cat > "$TMP/Cargo.toml" <<'EOF'
[package]
name = "x"
version = "0.1.0"
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "cargo test" ] && ok "7.1 test" || ko "7.1"
[ "$(echo "$out" | jq -r '.typecheck_command')" = "cargo check" ] && ok "7.2 check" || ko "7.2"
[ "$(echo "$out" | jq -r '.lint_command')" = "cargo clippy -- -D warnings" ] && ok "7.3 clippy" || ko "7.3"
[ "$(echo "$out" | jq -r '.format_command')" = "cargo fmt" ] && ok "7.4 fmt" || ko "7.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 8. Python pyproject.toml
echo ""
echo "[8] pyproject.toml with pytest+mypy+ruff+black"
TMP=$(mktemp -d)
cat > "$TMP/pyproject.toml" <<'EOF'
[tool.pytest.ini_options]
testpaths = ["tests"]

[tool.mypy]
strict = true

[tool.ruff]
line-length = 100

[tool.black]
line-length = 100
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "pytest" ] && ok "8.1 pytest" || ko "8.1"
[ "$(echo "$out" | jq -r '.typecheck_command')" = "mypy ." ] && ok "8.2 mypy" || ko "8.2"
[ "$(echo "$out" | jq -r '.lint_command')" = "ruff check ." ] && ok "8.3 ruff" || ko "8.3"
[ "$(echo "$out" | jq -r '.format_command')" = "black ." ] && ok "8.4 black" || ko "8.4"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 9. Makefile targets
echo ""
echo "[9] Makefile targets"
TMP=$(mktemp -d)
cat > "$TMP/Makefile" <<'EOF'
test:
	go test ./...

lint:
	golangci-lint run

typecheck:
	go vet ./...
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "make test" ] && ok "9.1 make test" || ko "9.1"
[ "$(echo "$out" | jq -r '.lint_command')" = "make lint" ] && ok "9.2 make lint" || ko "9.2"
[ "$(echo "$out" | jq -r '.typecheck_command')" = "make typecheck" ] && ok "9.3 make typecheck" || ko "9.3"
echo "$out" | jq -e 'has("format_command") | not' >/dev/null && ok "9.4 no format target omitted" || ko "9.4 leaked"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 10. Multi-source first-match-wins (npm wins over make for same slot)
echo ""
echo "[10] npm beats make (default order)"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
cat > "$TMP/Makefile" <<'EOF'
test:
	go test ./...
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "npm run test" ] && ok "10.1 npm wins" || ko "10.1 got $(echo "$out" | jq -r '.test_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 11. --prefer reorders sources
echo ""
echo "[11] --prefer=make"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
cat > "$TMP/Makefile" <<'EOF'
test:
	go test ./...
EOF
out=$(bash "$SCRIPT" --project-root="$TMP" --prefer=make)
[ "$(echo "$out" | jq -r '.test_command')" = "make test" ] && ok "11.1 make wins" || ko "11.1 got $(echo "$out" | jq -r '.test_command')"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 12. Partial fill from secondary source
echo ""
echo "[12] npm test + cargo lint fallback"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
cat > "$TMP/Cargo.toml" <<'EOF'
[package]
name = "x"
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$(echo "$out" | jq -r '.test_command')" = "npm run test" ] && ok "12.1 test from npm" || ko "12.1"
[ "$(echo "$out" | jq -r '.lint_command')" = "cargo clippy -- -D warnings" ] && ok "12.2 lint from cargo" || ko "12.2"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 13. Invalid --prefer
echo ""
echo "[13] invalid --prefer"
bash "$SCRIPT" --prefer=foo >/dev/null 2>&1
[ $? -ne 0 ] && ok "13.1 invalid prefer rejected" || ko "13.1 accepted"

# 14. Non-existent project root
echo ""
echo "[14] missing project root"
bash "$SCRIPT" --project-root=/nonexistent/path >/dev/null 2>&1
[ $? -ne 0 ] && ok "14.1 missing dir rejected" || ko "14.1 accepted"

# 15. Output is valid JSON
echo ""
echo "[15] output JSON"
TMP=$(mktemp -d)
cat > "$TMP/package.json" <<'EOF'
{ "scripts": { "test": "vitest" } }
EOF
out=$(bash "$SCRIPT" --project-root="$TMP")
echo "$out" | jq empty 2>/dev/null && ok "15.1 valid JSON" || ko "15.1 invalid JSON: $out"
trash "$TMP" 2>/dev/null || rm -rf "$TMP"

# 16. Malformed package.json fallback
echo ""
echo "[16] malformed package.json"
TMP=$(mktemp -d)
echo "not json" > "$TMP/package.json"
out=$(bash "$SCRIPT" --project-root="$TMP")
[ "$out" = "{}" ] && ok "16.1 graceful empty" || ko "16.1 got '$out'"
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
