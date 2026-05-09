#!/usr/bin/env bash
# resume-state.sh — Compute the next step to run for a /<skill> --resume invocation.
#
# Reads .claude/product/progress.md (and per-feature progress files), finds the last
# successful step for the given skill, and prints the next step's identifier and
# (optionally) the matched feature_id for partial-match resume.
#
# Subcommands:
#   next --skill=NAME [--feature=PARTIAL] [--project-root=PATH]
#       Print the next step name (e.g. "step-03-features") on stdout, plus the
#       resolved feature_id if partial-match was used. Output is a JSON object:
#         {"next_step":"step-03-features","feature_id":"01-auth","matched":true,"reason":"..."}
#       Exit 0 = match found; exit 1 = no in-flight run (caller should fall through
#       to step-00); exit 2 = bad args.
#
# Partial-match rules for --feature:
#   - exact slug match preferred (01-auth == "01-auth")
#   - prefix on the numeric part: "01" matches "01-auth"
#   - prefix on the slug: "auth" matches "01-auth"
#   - case-insensitive
#   - if multiple matches and no exact, fail with exit 1 + suggestion list
#
# Usage: resume-state.sh next --skill=define [--feature=01]

set -euo pipefail

PROJECT_ROOT="${ARTYSAN_PROJECT_ROOT:-$(pwd)}"

usage() {
  cat <<'EOF'
Usage: resume-state.sh next --skill=NAME [--feature=PARTIAL] [--project-root=PATH]

Resolve the next step for a --resume invocation. Reads progress.md (global +
per-feature) and infers the next step from the last successful entry for the skill.

Output (stdout): JSON {next_step, feature_id, matched, reason}
Exit codes: 0 = match, 1 = no in-flight run, 2 = bad args
EOF
}

cmd_next() {
  local skill="" feature=""
  for a in "$@"; do
    case "$a" in
      --skill=*)        skill="${a#--skill=}" ;;
      --feature=*)      feature="${a#--feature=}" ;;
      --project-root=*) PROJECT_ROOT="${a#--project-root=}" ;;
      -h|--help)        usage; return 0 ;;
      *) echo "ERROR: unknown arg: $a" >&2; return 2 ;;
    esac
  done

  [ -n "$skill" ] || { echo "ERROR: --skill required" >&2; return 2; }

  local progress="${PROJECT_ROOT}/.claude/product/progress.md"

  # Resolve feature_id if --feature given (partial match)
  local resolved_feature=""
  if [ -n "$feature" ]; then
    local features_dir="${PROJECT_ROOT}/.claude/product/features"
    [ -d "$features_dir" ] || {
      jq -n --arg f "$feature" '{"error":("no features dir; cannot resolve "+$f)}' >&2
      return 1
    }

    # Lowercase target for case-insensitive comparison.
    local lc_feat
    lc_feat=$(echo "$feature" | tr '[:upper:]' '[:lower:]')

    local candidates=()
    while IFS= read -r d; do
      local fid
      fid=$(basename "$d")
      candidates+=("$fid")
    done < <(find "$features_dir" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

    if [ "${#candidates[@]}" -eq 0 ]; then
      jq -n --arg f "$feature" '{"error":("no feature dirs; cannot resolve "+$f)}' >&2
      return 1
    fi

    # 1. exact match (case-insensitive).
    for c in "${candidates[@]}"; do
      local lc_c
      lc_c=$(echo "$c" | tr '[:upper:]' '[:lower:]')
      if [ "$lc_c" = "$lc_feat" ]; then
        resolved_feature="$c"
        break
      fi
    done

    # 2. prefix on numeric part (e.g. "01" matches "01-auth")
    if [ -z "$resolved_feature" ]; then
      local matches=()
      for c in "${candidates[@]}"; do
        local lc_c num
        lc_c=$(echo "$c" | tr '[:upper:]' '[:lower:]')
        num="${lc_c%%-*}"
        if [ "$num" = "$lc_feat" ]; then
          matches+=("$c")
        fi
      done
      if [ "${#matches[@]}" -eq 1 ]; then
        resolved_feature="${matches[0]}"
      elif [ "${#matches[@]}" -gt 1 ]; then
        echo "ERROR: ambiguous --feature='$feature' matches: ${matches[*]}" >&2
        return 1
      fi
    fi

    # 3. prefix on slug (e.g. "auth" matches "01-auth")
    if [ -z "$resolved_feature" ]; then
      local matches=()
      for c in "${candidates[@]}"; do
        local lc_c slug
        lc_c=$(echo "$c" | tr '[:upper:]' '[:lower:]')
        slug="${lc_c#*-}"
        case "$slug" in
          "$lc_feat"*) matches+=("$c") ;;
        esac
      done
      if [ "${#matches[@]}" -eq 1 ]; then
        resolved_feature="${matches[0]}"
      elif [ "${#matches[@]}" -gt 1 ]; then
        echo "ERROR: ambiguous --feature='$feature' matches: ${matches[*]}" >&2
        return 1
      fi
    fi

    if [ -z "$resolved_feature" ]; then
      echo "ERROR: --feature='$feature' did not match any feature dir; candidates: ${candidates[*]}" >&2
      return 1
    fi
  fi

  # Choose progress file to scan: per-feature if resolved, else global.
  local scan_file=""
  if [ -n "$resolved_feature" ]; then
    local pf="${PROJECT_ROOT}/.claude/product/features/${resolved_feature}/progress.md"
    [ -f "$pf" ] && scan_file="$pf"
  fi
  if [ -z "$scan_file" ] && [ -f "$progress" ]; then
    scan_file="$progress"
  fi
  if [ -z "$scan_file" ]; then
    jq -n --arg r "no progress.md" --arg fid "$resolved_feature" \
      '{"next_step":"step-00-init", "feature_id":$fid, "matched":false, "reason":$r}'
    return 1
  fi

  # Find last entry for this skill with status=ok.
  # update-progress.sh writes lines like: "- [TIMESTAMP] skill step-NN name — ok"
  local last_line
  last_line=$(grep -E "^\- \[" "$scan_file" 2>/dev/null \
    | grep -E " ${skill} step-[0-9]{2} " \
    | grep -E " (ok|skip)$" \
    | tail -n 1 || true)

  if [ -z "$last_line" ]; then
    jq -n --arg r "no successful $skill step in $scan_file" --arg fid "$resolved_feature" \
      '{"next_step":"step-00-init", "feature_id":$fid, "matched":false, "reason":$r}'
    return 1
  fi

  # Extract step-NN-name token. Format: "skill step-NN <name> — status"
  local last_step
  last_step=$(echo "$last_line" | grep -oE "step-[0-9]{2}[a-z]?[[:space:]]+[a-z][a-z0-9-]*" \
    | head -n 1 \
    | awk '{printf "%s-%s", $1, $2}')

  # Compute next: increment NN, drop name suffix (caller's skill knows it).
  local nn next_step
  nn=$(echo "$last_step" | sed -E 's/^step-([0-9]{2})[a-z]?-.*/\1/')
  local next_nn
  next_nn=$(printf "%02d" $((10#$nn + 1)))
  next_step="step-${next_nn}"

  jq -n \
    --arg ns "$next_step" \
    --arg fid "$resolved_feature" \
    --arg ls "$last_step" \
    '{next_step:$ns, feature_id:$fid, matched:true, last_step:$ls, reason:("resumed from "+$ls)}'
}

# Main
[ $# -ge 1 ] || { usage >&2; exit 2; }
case "$1" in
  next)        shift; cmd_next "$@" ;;
  -h|--help)   usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $1" >&2; usage >&2; exit 2 ;;
esac
