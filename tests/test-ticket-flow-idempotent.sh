#!/usr/bin/env bash
# /ticket idempotent push — two consecutive pushes of the same title under
# --idempotency-check=true yield one tracker ticket (lookup-by-title gate).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER="${ROOT}/skills/_shared/tickets-adapter.sh"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1 — $2"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

DIR=$(mktemp -d -t snap-tk-idem-XXXXXX)
trap 'trash "$DIR" 2>/dev/null || true' EXIT

# Stub gh : first invocation `issue list --search` returns []; subsequent
# `issue list` returns the just-created ticket so the second create is
# deduped.
STATE_FILE="${DIR}/gh-state"
echo "fresh" > "$STATE_FILE"

cat > "${DIR}/gh" <<'STUB'
#!/usr/bin/env bash
state_file="$(dirname "$0")/gh-state"
state=$(cat "$state_file" 2>/dev/null || echo "fresh")
case "${1:-}-${2:-}" in
  issue-list)
    if [ "$state" = "fresh" ]; then
      echo "[]"
    else
      cat <<JSON
[{"number":42,"title":"Reuse me","url":"https://github.com/o/r/issues/42"}]
JSON
    fi
    ;;
  issue-create)
    echo "https://github.com/o/r/issues/42"
    echo "after-create" > "$state_file"
    ;;
  *) echo "stub: unknown gh args: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "${DIR}/gh"

echo "=== /ticket idempotent push ==="

# Push #1 — fresh state, create succeeds.
out1=$(SNAP_GH_BIN="${DIR}/gh" bash "$ADAPTER" --action=create \
  --platform=github --project-root="$DIR" \
  --title="Reuse me" --idempotency-check=true 2>&1)
rc1=$?
[ "$rc1" = "0" ] && ok "idem.1 first push exit 0" || ko "idem.1" "rc=$rc1 out=$out1"
pid1=$(jq -r '.result.platform_id' <<<"$out1")
[ "$pid1" = "42" ] && ok "idem.2 first push platform_id=42" || ko "idem.2" "pid=$pid1"
dedup1=$(jq -r '.result.deduped // false' <<<"$out1")
[ "$dedup1" = "false" ] && ok "idem.3 first push not deduped" || ko "idem.3" "deduped=$dedup1"

# Push #2 — same title, lookup returns the existing ticket → deduped.
out2=$(SNAP_GH_BIN="${DIR}/gh" bash "$ADAPTER" --action=create \
  --platform=github --project-root="$DIR" \
  --title="Reuse me" --idempotency-check=true 2>&1)
rc2=$?
[ "$rc2" = "0" ] && ok "idem.4 second push exit 0" || ko "idem.4" "rc=$rc2 out=$out2"
pid2=$(jq -r '.result.platform_id' <<<"$out2")
[ "$pid2" = "42" ] && ok "idem.5 second push reused platform_id=42" \
  || ko "idem.5" "pid=$pid2"
dedup2=$(jq -r '.result.deduped // false' <<<"$out2")
[ "$dedup2" = "true" ] && ok "idem.6 second push flagged deduped" \
  || ko "idem.6" "deduped=$dedup2 out=$out2"

# Mismatched title → no dedup (sanity).
out3=$(SNAP_GH_BIN="${DIR}/gh" bash "$ADAPTER" --action=create \
  --platform=github --project-root="$DIR" \
  --title="Different title" --idempotency-check=true 2>&1)
dedup3=$(jq -r '.result.deduped // false' <<<"$out3")
[ "$dedup3" = "false" ] && ok "idem.7 mismatched title not deduped" \
  || ko "idem.7" "deduped=$dedup3"

echo ""
echo "=== Summary ==="
echo "Passed: ${PASS}"
echo "Failed: ${FAIL}"
[ "$FAIL" -gt 0 ] && { printf '  - %s\n' "${ERRORS[@]}"; exit 1; }
exit 0
