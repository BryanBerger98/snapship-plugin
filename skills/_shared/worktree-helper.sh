#!/usr/bin/env bash
# worktree-helper.sh — Resolve git-worktree strategy per ticket (v1.2).
#
# v1.2 worktree strategy (decisions #5, #11) :
#   - Epic       → no branch, no worktree (error if resolve invoked).
#   - User Story → dedicated worktree {config.path}/{branch_name}.
#   - Bug        → dedicated worktree.
#   - Task whose parent is User Story → reuse parent US worktree (same branch).
#   - Task whose parent is Bug, Epic, or none → dedicated worktree.
#
# This helper is platform-agnostic : it only manipulates ticket JSON and config
# JSON. Live tracker lookup (parent fetch) is the caller's responsibility — pass
# the parent ticket JSON via --parent-json when relevant.
#
# Subcommands:
#   resolve   --ticket-json=<json> [--parent-json=<json>] [--config-json=<json>]
#                 Stdout: JSON {strategy, branch_name, worktree_path}.
#                 strategy ∈ {dedicated, reuse}.
#                 Exit 1 if story_type=epic or branch_name missing.
#
#   path <branch_name> [--config-json=<json>]
#                 Stdout: composed worktree path = {config.path}/<branch_name>.
#
#   destroy-decision --phase=<develop|review|merge>
#                    --config-destroy=<after_develop|after_review|after_merge>
#                 Exit 0 = destroy now, 1 = keep alive.
#
# Common options:
#   --project-root=PATH    Default: $SNAP_PROJECT_ROOT or $PWD.
#   -h, --help             Show this help.
#
# When --config-json is omitted, helper invokes load-config.sh to resolve
# defaults.worktree.{path, destroy}. Pass --config-json explicitly for tests
# or when config is already in memory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${SNAP_PROJECT_ROOT:-$(pwd)}"

usage() { sed -n '2,38p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

[ $# -lt 1 ] && { usage >&2; exit 1; }
CMD="$1"; shift

TICKET_JSON=""
PARENT_JSON=""
CONFIG_JSON=""
PHASE=""
CONFIG_DESTROY=""
POS_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --project-root=*)   PROJECT_ROOT="${1#--project-root=}" ;;
    --ticket-json=*)    TICKET_JSON="${1#--ticket-json=}" ;;
    --parent-json=*)    PARENT_JSON="${1#--parent-json=}" ;;
    --config-json=*)    CONFIG_JSON="${1#--config-json=}" ;;
    --phase=*)          PHASE="${1#--phase=}" ;;
    --config-destroy=*) CONFIG_DESTROY="${1#--config-destroy=}" ;;
    -h|--help)          usage; exit 0 ;;
    -*) echo "ERROR: unknown flag: $1" >&2; usage >&2; exit 1 ;;
    *)  POS_ARGS+=("$1") ;;
  esac
  shift
done

load_config_if_needed() {
  if [ -z "$CONFIG_JSON" ]; then
    CONFIG_JSON=$(SNAP_PROJECT_ROOT="$PROJECT_ROOT" \
      bash "${SCRIPT_DIR}/load-config.sh" --no-validate 2>/dev/null) \
      || { echo "ERROR: load-config.sh failed" >&2; exit 2; }
  fi
}

config_path() {
  echo "$CONFIG_JSON" | jq -r '.defaults.worktree.path // "./.worktrees"'
}

case "$CMD" in
  resolve)
    [ -z "$TICKET_JSON" ] && { echo "ERROR: --ticket-json required" >&2; exit 1; }
    load_config_if_needed

    story_type=$(echo "$TICKET_JSON" | jq -r '.story_type // ""')
    branch_name=$(echo "$TICKET_JSON" | jq -r '.branch_name // ""')

    case "$story_type" in
      epic)
        echo "ERROR: story_type=epic has no branch — worktree resolution forbidden" >&2
        exit 1
        ;;
      user-story|bug)
        [ -z "$branch_name" ] && {
          echo "ERROR: ticket missing branch_name (run apply-naming.sh first)" >&2
          exit 1
        }
        path="$(config_path)/${branch_name}"
        jq -n --arg s "dedicated" --arg b "$branch_name" --arg p "$path" \
          '{strategy:$s, branch_name:$b, worktree_path:$p}'
        ;;
      task)
        parent_story_id=$(echo "$TICKET_JSON" | jq -r '.parent_story_id // ""')
        parent_epic_id=$(echo "$TICKET_JSON" | jq -r '.parent_epic_id // ""')
        if [ -n "$parent_story_id" ] && [ "$parent_story_id" != "null" ]; then
          # Need parent story_type to decide reuse vs dedicated.
          [ -z "$PARENT_JSON" ] && {
            echo "ERROR: task has parent_story_id — pass --parent-json so strategy can be decided" >&2
            exit 1
          }
          parent_type=$(echo "$PARENT_JSON" | jq -r '.story_type // ""')
          parent_branch=$(echo "$PARENT_JSON" | jq -r '.branch_name // ""')
          if [ "$parent_type" = "user-story" ]; then
            [ -z "$parent_branch" ] && {
              echo "ERROR: parent user-story has no branch_name — cannot reuse" >&2
              exit 1
            }
            path="$(config_path)/${parent_branch}"
            jq -n --arg s "reuse" --arg b "$parent_branch" --arg p "$path" \
              '{strategy:$s, branch_name:$b, worktree_path:$p}'
          else
            # Parent is bug (or anything non-US) → dedicated.
            [ -z "$branch_name" ] && {
              echo "ERROR: task child of ${parent_type} needs its own branch_name" >&2
              exit 1
            }
            path="$(config_path)/${branch_name}"
            jq -n --arg s "dedicated" --arg b "$branch_name" --arg p "$path" \
              '{strategy:$s, branch_name:$b, worktree_path:$p}'
          fi
        else
          # Task child of Epic OR standalone → dedicated.
          [ -z "$branch_name" ] && {
            echo "ERROR: task ${parent_epic_id:+child of epic }standalone needs its own branch_name" >&2
            exit 1
          }
          path="$(config_path)/${branch_name}"
          jq -n --arg s "dedicated" --arg b "$branch_name" --arg p "$path" \
            '{strategy:$s, branch_name:$b, worktree_path:$p}'
        fi
        ;;
      "")
        echo "ERROR: ticket missing story_type" >&2
        exit 1
        ;;
      *)
        echo "ERROR: unknown story_type '${story_type}'" >&2
        exit 1
        ;;
    esac
    ;;

  path)
    [ "${#POS_ARGS[@]}" -eq 1 ] || { echo "ERROR: path <branch_name>" >&2; exit 1; }
    load_config_if_needed
    echo "$(config_path)/${POS_ARGS[0]}"
    ;;

  destroy-decision)
    [ -z "$PHASE" ] && { echo "ERROR: --phase required (develop|review|merge)" >&2; exit 1; }
    [ -z "$CONFIG_DESTROY" ] && { echo "ERROR: --config-destroy required" >&2; exit 1; }
    case "$PHASE" in
      develop|review|merge) ;;
      *) echo "ERROR: --phase must be develop|review|merge" >&2; exit 1 ;;
    esac
    case "$CONFIG_DESTROY" in
      after_develop|after_review|after_merge) ;;
      *) echo "ERROR: --config-destroy must be after_develop|after_review|after_merge" >&2; exit 1 ;;
    esac
    # Phase ordinal : develop=1, review=2, merge=3.
    # config_destroy ordinal : after_develop=1, after_review=2, after_merge=3.
    # Destroy when phase >= config_destroy.
    phase_ord() {
      case "$1" in
        develop) echo 1 ;; review) echo 2 ;; merge) echo 3 ;;
        after_develop) echo 1 ;; after_review) echo 2 ;; after_merge) echo 3 ;;
      esac
    }
    p=$(phase_ord "$PHASE")
    c=$(phase_ord "$CONFIG_DESTROY")
    [ "$p" -ge "$c" ] && exit 0 || exit 1
    ;;

  -h|--help) usage; exit 0 ;;

  *) echo "ERROR: unknown subcommand: $CMD" >&2; usage >&2; exit 1 ;;
esac
