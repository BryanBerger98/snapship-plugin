#!/usr/bin/env bash
# Tests for skills/_shared/migrations/v0.6.0_to_v1.0.0.sh
# Usage: bash tests/test-migration-v060-to-v100.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/migrations/v0.6.0_to_v1.0.0.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t snap-mig-XXXXXX; }
ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

# Build a v0.6.0-style workspace under $DIR/.claude/product/
seed_v06() {
  local dir="$1"
  mkdir -p "${dir}/.claude/product/features/01-auth/wireframes"
  mkdir -p "${dir}/.claude/product/features/01-auth/design"
  # meta.json
  cat > "${dir}/.claude/product/features/01-auth/meta.json" <<'EOF'
{
  "feature_id": "01-auth",
  "feature_name": "Authentication",
  "state": "ticketed",
  "prd": { "platform": "notion", "page_id": "page-xyz", "url": "https://notion.so/p/page-xyz" }
}
EOF
  echo "# PRD content" > "${dir}/.claude/product/features/01-auth/prd-feature.md"
  echo '[{"ticket_id":"AUTH-1"}]' > "${dir}/.claude/product/features/01-auth/tickets.json"
  echo "wireframe-asset" > "${dir}/.claude/product/features/01-auth/wireframes/login.svg"
  echo "design-asset" > "${dir}/.claude/product/features/01-auth/design/login.png"
  # domains.json
  cat > "${dir}/.claude/product/domains.json" <<'EOF'
{
  "auth": {
    "title": "Authentication",
    "domain_page_id": "dom-page-1",
    "domain_url": "https://notion.so/dom-page-1",
    "created_at": "2025-01-01T00:00:00Z",
    "journeys": {
      "signup": { "page_id": "j-page-1", "title": "Sign up" }
    }
  }
}
EOF
  # snapship.config.json with old version
  cat > "${dir}/snapship.config.json" <<'EOF'
{ "version": "0.6.0", "tickets": { "platform": "github" } }
EOF
}

echo "=== migration v0.6.0 → v1.0.0 tests ==="

# 1. Idempotent on empty project (no .claude/product) → init .snap/
echo ""
echo "[1] empty project — init .snap/"
DIR=$(setup_dir)
SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" >/dev/null 2>&1
[ -d "${DIR}/.snap/manifests" ] && ok "1.1 .snap/ initialized" || ko "1.1"
[ -f "${DIR}/.snap/manifests/_taxonomy.json" ] && ok "1.2 _taxonomy.json present" || ko "1.2"
trash "$DIR" 2>/dev/null || true

# 2. Already migrated (.snap/ present, .claude/product/ absent) — skip
echo ""
echo "[2] already migrated → skip"
DIR=$(setup_dir)
mkdir -p "${DIR}/.snap/manifests"
out=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" 2>&1)
echo "$out" | grep -q "Déjà migré\|Skip" && ok "2.1 skipped" || ko "2.1 got: $out"
trash "$DIR" 2>/dev/null || true

# 3. Happy path — full v0.6 → v1.0
echo ""
echo "[3] happy path"
DIR=$(setup_dir)
seed_v06 "$DIR"
SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='{"old_workspace":"backup","republish_prds":"skip"}' bash "$SCRIPT" >/dev/null 2>&1

# manifest converted
M="${DIR}/.snap/manifests/01-auth.manifest.json"
[ -f "$M" ] && ok "3.1 manifest created" || ko "3.1"
[ "$(jq -r '.feature_id' "$M")" = "01-auth" ] && ok "3.2 feature_id" || ko "3.2"
[ "$(jq -r '.schema_version' "$M")" = "1.0.0" ] && ok "3.3 schema_version" || ko "3.3"
[ "$(jq -r '.refs.prd.page_id' "$M")" = "page-xyz" ] && ok "3.4 refs.prd.page_id" || ko "3.4"
[ "$(jq -r '.refs.prd.platform' "$M")" = "notion" ] && ok "3.5 refs.prd.platform" || ko "3.5"
[ "$(jq -r '.refs.prd.sync_status' "$M")" = "synced" ] && ok "3.6 sync_status" || ko "3.6"
[ "$(jq 'has("prd")' "$M")" = "false" ] && ok "3.7 legacy .prd dropped" || ko "3.7"

# tickets, wireframes, designs moved
[ -f "${DIR}/.snap/tickets/01-auth.json" ] && ok "3.8 tickets moved" || ko "3.8"
[ -f "${DIR}/.snap/wireframes/01-auth/login.svg" ] && ok "3.9 wireframes moved" || ko "3.9"
[ -f "${DIR}/.snap/designs/01-auth/login.png" ] && ok "3.10 designs moved" || ko "3.10"

# PRD dropped (already synced — refs.prd.page_id set)
[ ! -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "3.11 PRD not re-staged (already synced)" || ko "3.11"

# _taxonomy.json
TAX="${DIR}/.snap/manifests/_taxonomy.json"
[ -f "$TAX" ] && ok "3.12 _taxonomy.json present" || ko "3.12"
[ "$(jq -r '.domains.auth.page_id' "$TAX")" = "dom-page-1" ] && ok "3.13 domain page_id migrated" || ko "3.13"
[ "$(jq -r '.schema_version' "$TAX")" = "1.0.0" ] && ok "3.14 taxonomy schema_version" || ko "3.14"

# version bump
[ "$(jq -r '.version' "${DIR}/snapship.config.json")" = "1.0" ] && ok "3.15 config version bumped" || ko "3.15"

# backup created
ls -d "${DIR}"/.snap.bak-v0.6.0-* 2>/dev/null | head -1 | grep -q . && ok "3.16 backup created" || ko "3.16"
trash "$DIR" 2>/dev/null || true

# 4. republish_prds=refresh → PRD copied to staging
echo ""
echo "[4] republish_prds=refresh"
DIR=$(setup_dir)
seed_v06 "$DIR"
SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='{"old_workspace":"keep","republish_prds":"refresh"}' bash "$SCRIPT" >/dev/null 2>&1
[ -f "${DIR}/.snap/PRDs/01-auth.md" ] && ok "4.1 PRD re-staged" || ko "4.1"
[ -d "${DIR}/.claude/product" ] && ok "4.2 old dir kept (keep)" || ko "4.2"
trash "$DIR" 2>/dev/null || true

# 5. dry-run does nothing destructive
echo ""
echo "[5] dry-run"
DIR=$(setup_dir)
seed_v06 "$DIR"
out=$(SNAP_PROJECT_ROOT="$DIR" SNAP_DRY_RUN=true bash "$SCRIPT" 2>&1)
echo "$out" | grep -q "DRY:" && ok "5.1 prints DRY actions" || ko "5.1"
[ ! -f "${DIR}/.snap/manifests/01-auth.manifest.json" ] && ok "5.2 no manifest written" || ko "5.2"
# .snap/manifests dir scaffolded via setup-snap-dir runs in DRY though — but actual jq files not written
[ -d "${DIR}/.claude/product" ] && ok "5.3 old dir untouched" || ko "5.3"
trash "$DIR" 2>/dev/null || true

# 6. Invalid decision JSON
echo ""
echo "[6] invalid decisions JSON"
DIR=$(setup_dir)
seed_v06 "$DIR"
if SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='not json' bash "$SCRIPT" 2>/dev/null; then
  ko "6.1 should fail"
else
  ok "6.1 rejected"
fi
trash "$DIR" 2>/dev/null || true

# 7. Invalid old_workspace decision
echo ""
echo "[7] invalid old_workspace"
DIR=$(setup_dir)
seed_v06 "$DIR"
if SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='{"old_workspace":"bogus"}' bash "$SCRIPT" 2>/dev/null; then
  ko "7.1 should fail"
else
  ok "7.1 rejected"
fi
trash "$DIR" 2>/dev/null || true

# 8. Re-run after migration is no-op
echo ""
echo "[8] re-run idempotent"
DIR=$(setup_dir)
seed_v06 "$DIR"
SNAP_PROJECT_ROOT="$DIR" SNAP_DECISIONS_JSON='{"old_workspace":"trash"}' bash "$SCRIPT" >/dev/null 2>&1
# old dir gone after trash
out=$(SNAP_PROJECT_ROOT="$DIR" bash "$SCRIPT" 2>&1)
echo "$out" | grep -q "Déjà migré\|Skip" && ok "8.1 second run skips" || ko "8.1 got: $out"
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
