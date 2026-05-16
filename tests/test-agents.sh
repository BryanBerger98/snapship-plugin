#!/usr/bin/env bash
# Tests for agents/*.md frontmatter + return-format spec.
#
# Validates each agent file:
#   1. Starts with a YAML frontmatter block delimited by ---
#   2. Frontmatter has required keys: name, description
#   3. `name` matches the file basename
#   4. `tools` (if present) is a comma-separated list of known tool names
#   5. Body contains at least one ```json fence block (the return-format example)
#   6. The example JSON parses and has {severity, feedback_md} with a valid severity

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_DIR="${ROOT}/agents"

PASS=0
FAIL=0
ERRORS=()

ok() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
ko() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); ERRORS+=("$1"); }

VALID_SEVERITIES="none info minor major critical"
KNOWN_TOOLS="Read Write Edit Bash Grep Glob WebFetch WebSearch Task TaskCreate TaskUpdate TaskList NotebookEdit mcp__claude_ai_Context7__resolve-library-id mcp__claude_ai_Context7__query-docs"

extract_frontmatter() {
  awk '
    BEGIN { in_fm = 0; printed = 0 }
    /^---[[:space:]]*$/ {
      if (in_fm == 0) { in_fm = 1; next }
      else            { exit }
    }
    in_fm == 1 { print }
  ' "$1"
}

extract_first_json_fence() {
  awk '
    /^```json[[:space:]]*$/ { in_fence = 1; next }
    /^```[[:space:]]*$/     { if (in_fence) exit }
    in_fence { print }
  ' "$1"
}

# Get value of a top-level scalar key from frontmatter (no nested objects supported).
fm_get() {
  local fm="$1" key="$2"
  echo "$fm" | awk -v k="$key" '
    $0 ~ "^"k"[[:space:]]*:" {
      sub("^"k"[[:space:]]*:[[:space:]]*", "")
      sub("[[:space:]]+$", "")
      gsub(/^["'\'']|["'\'']$/, "")
      print
      exit
    }
  '
}

echo "=== agents tests ==="

shopt -s nullglob
files=("${AGENTS_DIR}"/*.md)

if [ "${#files[@]}" -eq 0 ]; then
  echo "no agents found in ${AGENTS_DIR}"
  echo "Passed: 0"
  echo "Failed: 0"
  exit 0
fi

for file in "${files[@]}"; do
  base=$(basename "$file" .md)
  echo ""
  echo "[$base]"

  fm=$(extract_frontmatter "$file")
  if [ -z "$fm" ]; then
    ko "$base: missing frontmatter"
    continue
  fi
  ok "$base: frontmatter present"

  name=$(fm_get "$fm" "name")
  desc=$(fm_get "$fm" "description")
  tools=$(fm_get "$fm" "tools")
  model=$(fm_get "$fm" "model")

  [ -n "$name" ] && ok "$base: has name"        || ko "$base: missing name"
  [ -n "$desc" ] && ok "$base: has description" || ko "$base: missing description"

  if [ "$name" = "$base" ]; then
    ok "$base: name matches filename"
  else
    ko "$base: name '$name' does not match filename '$base'"
  fi

  if [ -n "$tools" ]; then
    bad=""
    IFS=',' read -ra arr <<< "$tools"
    for t in "${arr[@]}"; do
      t_trim="${t#"${t%%[![:space:]]*}"}"; t_trim="${t_trim%"${t_trim##*[![:space:]]}"}"
      [ -z "$t_trim" ] && continue
      case " $KNOWN_TOOLS " in
        *" $t_trim "*) ;;
        *) bad="$bad $t_trim" ;;
      esac
    done
    if [ -n "$bad" ]; then
      ko "$base: unknown tools:$bad"
    else
      ok "$base: tools list valid ($tools)"
    fi
  fi

  if [ -n "$model" ]; then
    case "$model" in
      sonnet|opus|haiku|inherit) ok "$base: model valid ($model)" ;;
      *) ko "$base: model '$model' not in {sonnet,opus,haiku,inherit}" ;;
    esac
  fi

  json=$(extract_first_json_fence "$file")
  if [ -z "$json" ]; then
    ko "$base: no \`\`\`json fence in body (return-format example required)"
    continue
  fi
  ok "$base: json fence found"

  if echo "$json" | jq empty 2>/dev/null; then
    ok "$base: example JSON parses"
  else
    ko "$base: example JSON malformed"
    continue
  fi

  sev=$(echo "$json" | jq -r '.severity // empty')
  fb=$(echo "$json"  | jq -r '.feedback_md // empty')

  if [ -z "$sev" ]; then
    ko "$base: example missing 'severity'"
  else
    case " $VALID_SEVERITIES " in
      *" $sev "*) ok "$base: severity '$sev' valid" ;;
      *)         ko "$base: severity '$sev' not in {$VALID_SEVERITIES}" ;;
    esac
  fi

  if [ -z "$fb" ]; then
    ko "$base: example missing 'feedback_md'"
  else
    ok "$base: feedback_md present"
  fi
done

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
