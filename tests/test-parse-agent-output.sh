#!/usr/bin/env bash
# Tests for skills/_shared/parse-agent-output.sh

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${ROOT}/skills/_shared/parse-agent-output.sh"

PASS=0
FAIL=0
ERRORS=()

setup_dir() { mktemp -d -t artysan-parse-XXXXXX; }

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

echo "=== parse-agent-output.sh tests ==="

# 1. parse — single fence at end of agent output (typical case)
echo ""
echo "[1] parse — typical agent output"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
Some prose from the agent.

```json
{
  "severity": "minor",
  "feedback_md": "## Technical review\n\n- nit at src/foo.ts:42"
}
```
EOF

OUT=$(bash "$SCRIPT" parse --file="${DIR}/agent.md")
sev=$(echo "$OUT" | jq -r '.severity')
fb=$(echo "$OUT"  | jq -r '.feedback_md')
[ "$sev" = "minor" ] && ok "1.1 severity extracted" || ko "1.1 severity got '$sev'"
[ "$fb" = "## Technical review

- nit at src/foo.ts:42" ] && ok "1.2 feedback_md extracted" || ko "1.2 feedback_md mismatch"
trash "$DIR" 2>/dev/null || true

# 2. parse — reads from stdin
echo ""
echo "[2] parse — stdin"
OUT=$(printf 'preamble\n\n```json\n{"severity":"none","feedback_md":"clean"}\n```\n' | bash "$SCRIPT" parse)
sev=$(echo "$OUT" | jq -r '.severity')
[ "$sev" = "none" ] && ok "2.1 stdin parse works" || ko "2.1 stdin got '$sev'"

# 3. parse — multiple fences, takes the LAST
echo ""
echo "[3] parse — last fence wins"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
Example showing the format:

```json
{"severity":"info","feedback_md":"this is the example"}
```

Now the actual review:

```json
{"severity":"critical","feedback_md":"actual finding"}
```
EOF
OUT=$(bash "$SCRIPT" parse --file="${DIR}/agent.md")
sev=$(echo "$OUT" | jq -r '.severity')
fb=$(echo "$OUT" | jq -r '.feedback_md')
[ "$sev" = "critical" ] && ok "3.1 last fence chosen (severity)" || ko "3.1 got '$sev'"
[ "$fb" = "actual finding" ] && ok "3.2 last fence chosen (feedback)" || ko "3.2 got '$fb'"
trash "$DIR" 2>/dev/null || true

# 4. parse — missing fence rejected
echo ""
echo "[4] parse — missing fence"
DIR=$(setup_dir)
echo "no fence here" > "${DIR}/agent.md"
if bash "$SCRIPT" parse --file="${DIR}/agent.md" >/dev/null 2>&1; then
  ko "4.1 should have rejected missing fence"
else
  ok "4.1 rejected missing fence"
fi
trash "$DIR" 2>/dev/null || true

# 5. parse — malformed JSON rejected
echo ""
echo "[5] parse — malformed JSON"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
```json
{"severity": "minor", broken
```
EOF
if bash "$SCRIPT" parse --file="${DIR}/agent.md" >/dev/null 2>&1; then
  ko "5.1 should have rejected malformed JSON"
else
  ok "5.1 rejected malformed JSON"
fi
trash "$DIR" 2>/dev/null || true

# 6. parse — invalid severity rejected
echo ""
echo "[6] parse — invalid severity"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
```json
{"severity":"catastrophic","feedback_md":"bad sev"}
```
EOF
if bash "$SCRIPT" parse --file="${DIR}/agent.md" >/dev/null 2>&1; then
  ko "6.1 should have rejected invalid severity"
else
  ok "6.1 rejected invalid severity"
fi
trash "$DIR" 2>/dev/null || true

# 7. parse — missing severity field rejected
echo ""
echo "[7] parse — missing severity"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
```json
{"feedback_md":"no sev"}
```
EOF
if bash "$SCRIPT" parse --file="${DIR}/agent.md" >/dev/null 2>&1; then
  ko "7.1 should have rejected missing severity"
else
  ok "7.1 rejected missing severity"
fi
trash "$DIR" 2>/dev/null || true

# 8. parse — missing feedback_md rejected
echo ""
echo "[8] parse — missing feedback_md"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
```json
{"severity":"minor"}
```
EOF
if bash "$SCRIPT" parse --file="${DIR}/agent.md" >/dev/null 2>&1; then
  ko "8.1 should have rejected missing feedback_md"
else
  ok "8.1 rejected missing feedback_md"
fi
trash "$DIR" 2>/dev/null || true

# 9. parse — extra fields ignored (forward-compatible)
echo ""
echo "[9] parse — extra fields ignored"
DIR=$(setup_dir)
cat > "${DIR}/agent.md" <<'EOF'
```json
{"severity":"info","feedback_md":"ok","extra":"ignored","also":42}
```
EOF
OUT=$(bash "$SCRIPT" parse --file="${DIR}/agent.md")
keys=$(echo "$OUT" | jq -r 'keys | join(",")')
[ "$keys" = "feedback_md,severity" ] && ok "9.1 extra fields stripped" || ko "9.1 keys: $keys"
trash "$DIR" 2>/dev/null || true

# 10. rank — all severities
echo ""
echo "[10] rank — numeric ranks"
[ "$(bash "$SCRIPT" rank none)"     = "0" ] && ok "10.1 rank none=0"     || ko "10.1 rank none"
[ "$(bash "$SCRIPT" rank info)"     = "1" ] && ok "10.2 rank info=1"     || ko "10.2 rank info"
[ "$(bash "$SCRIPT" rank minor)"    = "2" ] && ok "10.3 rank minor=2"    || ko "10.3 rank minor"
[ "$(bash "$SCRIPT" rank major)"    = "3" ] && ok "10.4 rank major=3"    || ko "10.4 rank major"
[ "$(bash "$SCRIPT" rank critical)" = "4" ] && ok "10.5 rank critical=4" || ko "10.5 rank critical"

# 11. rank — invalid rejected
echo ""
echo "[11] rank — invalid"
if bash "$SCRIPT" rank bogus >/dev/null 2>&1; then
  ko "11.1 should have rejected bogus severity"
else
  ok "11.1 rejected bogus severity"
fi

# 12. max — picks highest
echo ""
echo "[12] max — highest wins"
[ "$(bash "$SCRIPT" max none info)"             = "info" ]     && ok "12.1 max(none,info)=info"   || ko "12.1"
[ "$(bash "$SCRIPT" max info major minor)"      = "major" ]    && ok "12.2 max(info,major,minor)" || ko "12.2"
[ "$(bash "$SCRIPT" max minor critical major)"  = "critical" ] && ok "12.3 critical wins"          || ko "12.3"
[ "$(bash "$SCRIPT" max none none none)"        = "none" ]     && ok "12.4 all none stays none"    || ko "12.4"
[ "$(bash "$SCRIPT" max critical)"              = "critical" ] && ok "12.5 single arg"             || ko "12.5"

# 13. aggregate — combine multiple reviewer outputs
echo ""
echo "[13] aggregate — multi-reviewer merge"
DIR=$(setup_dir)
cat > "${DIR}/tech.md" <<'EOF'
```json
{"severity":"minor","feedback_md":"## Technical review\n\n- nit at foo.ts:1"}
```
EOF
cat > "${DIR}/func.md" <<'EOF'
```json
{"severity":"major","feedback_md":"## Functional review\n\n- AC missing"}
```
EOF
cat > "${DIR}/sec.md" <<'EOF'
```json
{"severity":"none","feedback_md":"## Security review\n\nNo issues."}
```
EOF
OUT=$(bash "$SCRIPT" aggregate "${DIR}/tech.md" "${DIR}/func.md" "${DIR}/sec.md")
sev=$(echo "$OUT" | jq -r '.severity')
fb=$(echo "$OUT" | jq -r '.feedback_md')
[ "$sev" = "major" ] && ok "13.1 aggregate severity = max (major)" || ko "13.1 got '$sev'"
echo "$fb" | grep -q "## Technical review" && ok "13.2 contains tech section"  || ko "13.2 tech missing"
echo "$fb" | grep -q "## Functional review" && ok "13.3 contains func section" || ko "13.3 func missing"
echo "$fb" | grep -q "## Security review" && ok "13.4 contains sec section"    || ko "13.4 sec missing"
echo "$fb" | grep -q -- "---" && ok "13.5 sections separated by ---" || ko "13.5 separator missing"
trash "$DIR" 2>/dev/null || true

# 14. aggregate — single file works
echo ""
echo "[14] aggregate — single file"
DIR=$(setup_dir)
cat > "${DIR}/one.md" <<'EOF'
```json
{"severity":"info","feedback_md":"only one"}
```
EOF
OUT=$(bash "$SCRIPT" aggregate "${DIR}/one.md")
sev=$(echo "$OUT" | jq -r '.severity')
[ "$sev" = "info" ] && ok "14.1 single-file aggregate" || ko "14.1 got '$sev'"
trash "$DIR" 2>/dev/null || true

# 15. aggregate — propagates parse failure
echo ""
echo "[15] aggregate — parse failure propagates"
DIR=$(setup_dir)
cat > "${DIR}/good.md" <<'EOF'
```json
{"severity":"minor","feedback_md":"ok"}
```
EOF
echo "no fence" > "${DIR}/bad.md"
if bash "$SCRIPT" aggregate "${DIR}/good.md" "${DIR}/bad.md" >/dev/null 2>&1; then
  ko "15.1 should have failed on bad file"
else
  ok "15.1 failed on bad file"
fi
trash "$DIR" 2>/dev/null || true

# 16. usage — no args fails with exit 2
echo ""
echo "[16] usage"
bash "$SCRIPT" >/dev/null 2>&1
[ $? -eq 2 ] && ok "16.1 no-args returns exit 2" || ko "16.1 wrong exit code"

bash "$SCRIPT" --help >/dev/null
[ $? -eq 0 ] && ok "16.2 --help returns 0" || ko "16.2 --help bad exit"

bash "$SCRIPT" bogus_cmd >/dev/null 2>&1
[ $? -eq 2 ] && ok "16.3 unknown subcommand returns 2" || ko "16.3 wrong exit code"

# 17. parse — non-existent file rejected
echo ""
echo "[17] parse — missing file"
if bash "$SCRIPT" parse --file=/nonexistent/path/foo.md >/dev/null 2>&1; then
  ko "17.1 should have rejected missing file"
else
  ok "17.1 rejected missing file"
fi

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
