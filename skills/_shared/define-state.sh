#!/usr/bin/env bash
# define-state.sh — Read/write/validate the /define working state file.
#
# Working file: .snap/.define-state.json
# Purpose: cumulative state collected by step-01..03 of /define, consumed by
# step-04 to render templates. Cleaned up by step-05 on success.
#
# Subcommands:
#   init [--lang=fr|en] [--define-mode=vision|journey|story]
#        [--codebase-mode=greenfield|extension] [--story=NN-slug]
#                         Create OR merge-update the state file. If the file
#                         already exists, only the flags passed are updated —
#                         other keys (define_mode, codebase_mode, vision, …)
#                         are preserved. Safe to call from multiple steps.
#                         `--story-id=` is accepted as a synonym of `--story=`.
#                         `--feature=` is a deprecated alias of `--story=` and
#                         emits a stderr warning.
#   set KEY VALUE         Set a top-level scalar key (vision, north_star_metric,
#                         north_star_current, north_star_target, target_horizon,
#                         lang, define_mode, codebase_mode, active_story_id,
#                         cli_parent_epic_id).
#   get KEY               Print scalar value (empty if unset).
#   add-persona JSON      Append a persona object {persona_name, persona_role,
#                         persona_goals, persona_pains, persona_tools}.
#   add-feature JSON      Append a feature object (see schema in body).
#   list-personas         Emit personas as NDJSON.
#   list-features         Emit features as NDJSON.
#   validate              Run schema-style checks; exit 0 if OK, 1 if invalid.
#                         Prints findings on stderr.
#   validate-feature STORY_ID
#                         Validate a single feature in isolation (same per-
#                         feature rules as `validate`, scoped to one
#                         story_id). Exit 0 if OK, 1 if invalid, 2 on unknown
#                         story_id or arg-count error. Cross-feature checks
#                         (duplicates, ≥1 must) stay in `validate`.
#   validate-out-of-scope STRING
#                         Deterministic check for the per-feature out_of_scope
#                         field. Exit 0 if OK, 1 if reject. Reasons emitted on
#                         stderr: `too-short` (<20 chars after trim) or
#                         `placeholder-match` (case-insensitive equal to one of
#                         "the rest", "tout le reste", "n/a", "na", "tbd").
#   path                  Print absolute path to state file.
#   wipe                  Delete state file (called by step-05 on success).
#
# Validation rules (validate subcommand):
#   - vision present, ≥50 chars, contains a verb (heuristic: at least one word
#     ending in -s/-es/-ed/-ing/-ize/-ise OR a known small verb list)
#   - north_star_metric, current, target, horizon all non-empty
#   - personas array non-empty; each has role + goals + pains
#   - features array non-empty; ≥1 has priority=must; no duplicate story_id
#   - For each "refined" feature: problem_statement ≥30 chars, ≥1 AC,
#     in_scope/out_of_scope non-empty, solution_overview non-empty
#
# Usage: define-state.sh <subcommand> [args] [--project-root=PATH]

set -euo pipefail

PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

state_file() { echo "${PROJECT_ROOT}/.snap/.define-state.json"; }

usage() {
  cat <<'EOF'
Usage: define-state.sh <subcommand> [args] [--project-root=PATH]

Subcommands:
  init [--lang=…] [--define-mode=…] [--codebase-mode=…] [--story=…]
       (alias: --story-id=…; deprecated alias: --feature=…)
  set KEY VALUE
  get KEY
  add-persona JSON
  add-feature JSON
  list-personas
  list-features
  validate
  validate-feature STORY_ID
  validate-out-of-scope STRING
  path
  wipe
  -h, --help
EOF
}

# Parse global --project-root from anywhere in args (extracts and removes it).
parse_project_root() {
  local out=()
  for a in "$@"; do
    case "$a" in
      --project-root=*) PROJECT_ROOT="${a#--project-root=}" ;;
      *) out+=("$a") ;;
    esac
  done
  if [ "${#out[@]}" -eq 0 ]; then
    REMAINING=()
  else
    REMAINING=("${out[@]}")
  fi
}

ensure_state() {
  local f
  f=$(state_file)
  [ -f "$f" ] || { echo "ERROR: state file missing: $f" >&2; return 1; }
}

cmd_init() {
  local lang="" define_mode="" codebase_mode="" story=""
  # Track which flags were explicitly passed (so merge updates only those keys).
  local set_lang=0 set_define_mode=0 set_codebase_mode=0 set_story=0
  for a in "$@"; do
    case "$a" in
      --lang=*)           lang="${a#--lang=}";                     set_lang=1 ;;
      --define-mode=*)    define_mode="${a#--define-mode=}";       set_define_mode=1 ;;
      --codebase-mode=*)  codebase_mode="${a#--codebase-mode=}";   set_codebase_mode=1 ;;
      --story=*)          story="${a#--story=}";                   set_story=1 ;;
      --story-id=*)       story="${a#--story-id=}";                set_story=1 ;;
      --feature=*)
        echo "WARNING: --feature= is deprecated; use --story= instead" >&2
        story="${a#--feature=}";                                   set_story=1 ;;
      --mode=*)
        echo "WARNING: --mode= is deprecated; pass --define-mode= or --codebase-mode= explicitly" >&2
        return 2 ;;
      *) echo "ERROR: unknown arg: $a" >&2; return 2 ;;
    esac
  done
  local f
  f=$(state_file)
  mkdir -p "$(dirname "$f")"

  if [ ! -f "$f" ]; then
    # First call — create the full skeleton.
    jq -n \
      --arg lang "$lang" \
      --arg define_mode "$define_mode" \
      --arg codebase_mode "$codebase_mode" \
      --arg story "$story" \
      --arg created "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      '{
        created_at: $created,
        lang: $lang,
        define_mode: $define_mode,
        codebase_mode: $codebase_mode,
        active_story_id: $story,
        cli_parent_epic_id: "",
        vision: "",
        north_star_metric: "",
        north_star_current: "",
        north_star_target: "",
        target_horizon: "",
        personas: [],
        features: []
      }' > "$f"
    return 0
  fi

  # Merge — only update keys whose flag was explicitly passed.
  local tmp
  tmp=$(mktemp)
  jq \
    --arg lang "$lang" \
    --arg define_mode "$define_mode" \
    --arg codebase_mode "$codebase_mode" \
    --arg story "$story" \
    --argjson set_lang "$set_lang" \
    --argjson set_define_mode "$set_define_mode" \
    --argjson set_codebase_mode "$set_codebase_mode" \
    --argjson set_story "$set_story" \
    '
      (if $set_lang == 1 then .lang = $lang else . end)
      | (if $set_define_mode == 1 then .define_mode = $define_mode else . end)
      | (if $set_codebase_mode == 1 then .codebase_mode = $codebase_mode else . end)
      | (if $set_story == 1 then .active_story_id = $story else . end)
    ' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_set() {
  ensure_state
  [ $# -eq 2 ] || { echo "ERROR: set KEY VALUE" >&2; return 2; }
  local key="$1" val="$2"
  case "$key" in
    vision|north_star_metric|north_star_current|north_star_target|target_horizon|\
lang|define_mode|codebase_mode|active_story_id|cli_parent_epic_id) ;;
    *) echo "ERROR: unsupported key: $key" >&2; return 2 ;;
  esac
  local f tmp
  f=$(state_file)
  tmp=$(mktemp)
  jq --arg k "$key" --arg v "$val" '.[$k] = $v' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_get() {
  ensure_state
  [ $# -eq 1 ] || { echo "ERROR: get KEY" >&2; return 2; }
  jq -r --arg k "$1" '.[$k] // ""' "$(state_file)"
}

cmd_add_persona() {
  ensure_state
  [ $# -eq 1 ] || { echo "ERROR: add-persona JSON" >&2; return 2; }
  echo "$1" | jq empty 2>/dev/null || { echo "ERROR: invalid JSON" >&2; return 1; }
  local f tmp
  f=$(state_file)
  tmp=$(mktemp)
  jq --argjson p "$1" '.personas += [$p]' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_add_feature() {
  ensure_state
  [ $# -eq 1 ] || { echo "ERROR: add-feature JSON" >&2; return 2; }
  echo "$1" | jq empty 2>/dev/null || { echo "ERROR: invalid JSON" >&2; return 1; }
  local f tmp
  f=$(state_file)
  tmp=$(mktemp)
  jq --argjson x "$1" '.features += [$x]' "$f" > "$tmp" && mv "$tmp" "$f"
}

cmd_list_personas() {
  ensure_state
  jq -c '.personas[]' "$(state_file)"
}

cmd_list_features() {
  ensure_state
  jq -c '.features[]' "$(state_file)"
}

cmd_path() {
  echo "$(state_file)"
}

cmd_wipe() {
  local f
  f=$(state_file)
  [ -f "$f" ] && rm -f "$f"
  return 0
}

cmd_validate_out_of_scope() {
  [ $# -eq 1 ] || { echo "ERROR: validate-out-of-scope STRING" >&2; return 2; }
  local raw="$1" trimmed lc
  # Trim leading/trailing whitespace.
  trimmed="${raw#"${raw%%[![:space:]]*}"}"
  trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
  lc=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
  # Placeholder check runs first so short canonical non-answers ("TBD", "N/A")
  # surface a clearer reason than "too-short".
  case "$lc" in
    "the rest"|"tout le reste"|"n/a"|"na"|"tbd")
      echo "out_of_scope: placeholder-match (\"$trimmed\" is a non-answer)" >&2
      return 1
      ;;
  esac
  if [ "${#trimmed}" -lt 20 ]; then
    echo "out_of_scope: too-short (got ${#trimmed} chars, need ≥20 after trim)" >&2
    return 1
  fi
  return 0
}

# Per-feature validation (reused by `validate` and `validate-feature`).
# Reads a single feature JSON object on stdin-style arg. Echoes one error line
# per finding on stdout. Returns 0 if no errors, 1 otherwise.
_check_feature_obj() {
  local feat="$1"
  local errs=()
  local status fid
  status=$(echo "$feat" | jq -r '.feature_status // "draft"')
  fid=$(echo "$feat" | jq -r '.story_id // "_anon_"')
  if [ "$status" = "refined" ]; then
    local ps so isc oos ac
    ps=$(echo "$feat"  | jq -r '.problem_statement // ""')
    so=$(echo "$feat"  | jq -r '.solution_overview // ""')
    isc=$(echo "$feat" | jq -r '.in_scope // ""')
    oos=$(echo "$feat" | jq -r '.out_of_scope // ""')
    ac=$(echo "$feat"  | jq '.acceptance_criteria // [] | length')
    [ "${#ps}" -ge 30 ] || errs+=("feature $fid: problem_statement <30 chars")
    [ -n "$so" ]        || errs+=("feature $fid: solution_overview empty")
    [ -n "$isc" ]       || errs+=("feature $fid: in_scope empty")
    if ! cmd_validate_out_of_scope "$oos" 2>/dev/null; then
      local oos_lc
      oos_lc=$(printf '%s' "$oos" | tr '[:upper:]' '[:lower:]')
      case "$oos_lc" in
        "the rest"|"tout le reste"|"n/a"|"na"|"tbd")
          errs+=("feature $fid: out_of_scope placeholder (\"$oos\")") ;;
        *)
          errs+=("feature $fid: out_of_scope too-short (<20 chars)") ;;
      esac
    fi
    [ "$ac" -ge 1 ]     || errs+=("feature $fid: no acceptance_criteria")
  fi
  if [ "${#errs[@]}" -eq 0 ]; then
    return 0
  fi
  printf '%s\n' "${errs[@]}"
  return 1
}

cmd_validate_feature() {
  [ $# -eq 1 ] || { echo "ERROR: validate-feature STORY_ID" >&2; return 2; }
  ensure_state
  local story_id="$1" f feat
  f=$(state_file)
  feat=$(jq -c --arg sid "$story_id" 'first(.features[] | select(.story_id == $sid)) // empty' "$f")
  if [ -z "$feat" ]; then
    echo "validate-feature: unknown story_id \"$story_id\"" >&2
    return 2
  fi
  local errs
  if errs=$(_check_feature_obj "$feat"); then
    echo "validate-feature: ok ($story_id)" >&2
    return 0
  fi
  printf 'validate-feature: FAIL (%s)\n' "$story_id" >&2
  while IFS= read -r line; do
    printf '  - %s\n' "$line" >&2
  done <<< "$errs"
  return 1
}

cmd_validate() {
  ensure_state
  local f
  f=$(state_file)
  local errs=()

  # vision — length check only. Anti-junk (verb / action sentence) is judged
  # by the LLM in step-01-vision before persistence (multilingual native).
  local vision
  vision=$(jq -r '.vision // ""' "$f")
  if [ "${#vision}" -lt 50 ]; then
    errs+=("vision: too short (got ${#vision} chars, need ≥50)")
  fi

  # north star scalars
  for k in north_star_metric north_star_current north_star_target target_horizon; do
    local v
    v=$(jq -r --arg k "$k" '.[$k] // ""' "$f")
    [ -n "$v" ] || errs+=("$k: empty")
  done

  # personas
  local pcount
  pcount=$(jq '.personas | length' "$f")
  if [ "$pcount" -lt 1 ]; then
    errs+=("personas: empty")
  else
    while IFS= read -r p; do
      for k in persona_role persona_goals persona_pains; do
        local v
        v=$(echo "$p" | jq -r --arg k "$k" '.[$k] // ""')
        [ -n "$v" ] || errs+=("persona $(echo "$p" | jq -r '.persona_name // "_anon_"'): missing $k")
      done
    done < <(jq -c '.personas[]' "$f")
  fi

  # features
  local fcount
  fcount=$(jq '.features | length' "$f")
  if [ "$fcount" -lt 1 ]; then
    errs+=("features: empty")
  else
    local must_count
    must_count=$(jq '[.features[] | select(.priority == "must")] | length' "$f")
    [ "$must_count" -ge 1 ] || errs+=("features: no must-priority feature")

    local dup
    dup=$(jq -r '[.features[].story_id] | group_by(.) | map(select(length > 1) | .[0]) | join(",")' "$f")
    [ -z "$dup" ] || errs+=("features: duplicate story_id(s): $dup")

    while IFS= read -r feat; do
      local feat_errs
      if ! feat_errs=$(_check_feature_obj "$feat"); then
        while IFS= read -r line; do
          errs+=("$line")
        done <<< "$feat_errs"
      fi
    done < <(jq -c '.features[]' "$f")
  fi

  if [ "${#errs[@]}" -eq 0 ]; then
    echo "validate: ok" >&2
    return 0
  fi
  printf 'validate: FAIL\n' >&2
  printf '  - %s\n' "${errs[@]}" >&2
  return 1
}

# Main
[ $# -ge 1 ] || { usage >&2; exit 2; }
SUBCMD="$1"; shift
parse_project_root "$@"

case "$SUBCMD" in
  init)                 cmd_init                 ${REMAINING[@]+"${REMAINING[@]}"} ;;
  set)                  cmd_set                  ${REMAINING[@]+"${REMAINING[@]}"} ;;
  get)                  cmd_get                  ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-persona)     cmd_add_persona   ${REMAINING[@]+"${REMAINING[@]}"} ;;
  add-feature)     cmd_add_feature   ${REMAINING[@]+"${REMAINING[@]}"} ;;
  list-personas)   cmd_list_personas ;;
  list-features)   cmd_list_features ;;
  validate)               cmd_validate                ;;
  validate-feature)       cmd_validate_feature        ${REMAINING[@]+"${REMAINING[@]}"} ;;
  validate-out-of-scope)  cmd_validate_out_of_scope   ${REMAINING[@]+"${REMAINING[@]}"} ;;
  path)            cmd_path          ;;
  wipe)            cmd_wipe          ;;
  -h|--help)       usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $SUBCMD" >&2; usage >&2; exit 2 ;;
esac
