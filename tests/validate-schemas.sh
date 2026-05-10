#!/usr/bin/env bash
# Run JSON Schema validation sur fixtures valid/ + invalid/
# Usage: bash tests/validate-schemas.sh
# Exit 0 = all pass, 1 = any fail

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMAS="${ROOT}/skills/_shared/schemas"
FIXTURES="${ROOT}/tests/fixtures"

# Vérifie ajv-cli dispo (npx fallback)
if command -v ajv >/dev/null 2>&1; then
  AJV="ajv"
elif command -v npx >/dev/null 2>&1; then
  AJV="npx -y ajv-cli"
else
  echo "ERROR: ajv-cli requis (npm i -g ajv-cli) ou npx" >&2
  exit 1
fi

PASS=0
FAIL=0
ERRORS=()

# args: schema_name (config|meta|tickets), expected_outcome (valid|invalid)
validate_dir() {
  local schema_name="$1"
  local expected="$2"
  local schema_file="${SCHEMAS}/${schema_name}.schema.json"
  local fixture_dir="${FIXTURES}/${expected}/${schema_name}"

  [ -d "$fixture_dir" ] || return 0

  for fixture in "${fixture_dir}"/*.json; do
    [ -f "$fixture" ] || continue
    local name
    name="$(basename "$fixture")"

    local output
    if output=$($AJV validate --spec=draft2020 -s "$schema_file" -d "$fixture" --strict=false 2>&1); then
      if [ "$expected" = "valid" ]; then
        echo "  PASS  ${schema_name}/${name}"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  ${schema_name}/${name} — schema accepted invalid fixture"
        FAIL=$((FAIL + 1))
        ERRORS+=("${expected}/${schema_name}/${name}: schema should reject but accepted")
      fi
    else
      if [ "$expected" = "invalid" ]; then
        echo "  PASS  ${schema_name}/${name} (rejected as expected)"
        PASS=$((PASS + 1))
      else
        echo "  FAIL  ${schema_name}/${name}"
        echo "        $output" | head -5
        FAIL=$((FAIL + 1))
        ERRORS+=("${expected}/${schema_name}/${name}: ${output}")
      fi
    fi
  done
}

echo "=== Valid fixtures (must pass schema) ==="
validate_dir "config" "valid"
validate_dir "meta" "valid"
validate_dir "tickets" "valid"
validate_dir "domains" "valid"

echo ""
echo "=== Invalid fixtures (must fail schema) ==="
validate_dir "config" "invalid"
validate_dir "meta" "invalid"
validate_dir "tickets" "invalid"
validate_dir "domains" "invalid"

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
