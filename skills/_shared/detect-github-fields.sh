#!/usr/bin/env bash
# detect-github-fields.sh — Discover GitHub org-level Issue Types + Projects v2
# fields available for a repository. Pure read; no side effects.
#
# Output JSON shape on stdout (exit 0):
#   {
#     "ok": true,
#     "owner": "<org-or-user>",
#     "repo": "<repo>",
#     "owner_type": "Organization" | "User",
#     "issue_types": [ { "id": "IT_xxx", "name": "Feature", "description": "" }, ... ],
#     "projects": [
#       {
#         "id": "PVT_xxx", "number": 12, "title": "SnapShip Project", "url": "...",
#         "fields": [
#           { "id": "PVTSSF_xxx", "name": "Priority", "data_type": "SINGLE_SELECT",
#             "options": [ { "id": "opt_xxx", "name": "P0" }, ... ] },
#           ...
#         ]
#       }
#     ]
#   }
#
# Errors:
#   exit 1 + {"ok":false,"error":"..."} on gh / network / parse failure.
#   exit 2 on bad arguments.
#
# Usage:
#   detect-github-fields.sh [--project-root=PATH] [--repo=owner/name]
#
# Defaults:
#   --project-root → $PWD
#   --repo         → derived from `gh repo view --json nameWithOwner` if omitted.
#
# Test hook: SNAP_GH_BIN may override the `gh` binary path.

set -euo pipefail

REPO=""

while [ $# -gt 0 ]; do
  case "$1" in
    # --project-root accepted for interface parity; this helper has no need for it.
    --project-root=*) : ;;
    --repo=*)         REPO="${1#--repo=}" ;;
    -h|--help)
      sed -n '1,30p' "$0"
      exit 0
      ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }

GH_BIN="${SNAP_GH_BIN:-gh}"
command -v "$GH_BIN" >/dev/null 2>&1 || {
  jq -nc '{ok:false, error:"gh CLI not installed"}'
  exit 1
}

err() {
  jq -nc --arg m "$1" '{ok:false, error:$m}'
  exit 1
}

# Resolve owner/name from gh if not provided.
if [ -z "$REPO" ]; then
  if ! REPO=$("$GH_BIN" repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null); then
    err "could not resolve current repo; pass --repo=owner/name"
  fi
fi

case "$REPO" in
  */*) ;;
  *)   err "invalid --repo: $REPO (expected owner/name)" ;;
esac
OWNER="${REPO%%/*}"
NAME="${REPO#*/}"
[ -n "$OWNER" ] && [ -n "$NAME" ] || err "invalid --repo: $REPO (expected owner/name)"

# --- Issue Types + owner kind (one GraphQL roundtrip) ---------------------
ISSUE_TYPES_QUERY='query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    owner{ __typename login }
    issueTypes(first:50){ nodes{ id name description } }
  }
}'

if ! IT_RAW=$("$GH_BIN" api graphql \
      -f query="$ISSUE_TYPES_QUERY" \
      -F owner="$OWNER" \
      -F name="$NAME" 2>&1); then
  # Issue Types is a recent feature; some orgs/users don't have it.
  # Treat any error as "no issue types" rather than fatal.
  IT_RAW='{"data":{"repository":{"owner":{"__typename":"Unknown","login":"'"$OWNER"'"},"issueTypes":{"nodes":[]}}}}'
fi

OWNER_TYPE=$(echo "$IT_RAW" | jq -r '.data.repository.owner.__typename // "Unknown"')
ISSUE_TYPES=$(echo "$IT_RAW" | jq -c '
  (.data.repository.issueTypes.nodes // [])
  | map({id, name, description: (.description // "")})')

# --- Projects v2 attached to repo + their single-select fields ----------
PROJECTS_QUERY='query($owner:String!,$name:String!){
  repository(owner:$owner,name:$name){
    projectsV2(first:20){
      nodes{
        id number title url
        fields(first:50){
          nodes{
            __typename
            ... on ProjectV2FieldCommon { id name dataType }
            ... on ProjectV2SingleSelectField {
              id name dataType
              options{ id name }
            }
          }
        }
      }
    }
  }
}'

if ! PR_RAW=$("$GH_BIN" api graphql \
      -f query="$PROJECTS_QUERY" \
      -F owner="$OWNER" \
      -F name="$NAME" 2>&1); then
  PR_RAW='{"data":{"repository":{"projectsV2":{"nodes":[]}}}}'
fi

PROJECTS=$(echo "$PR_RAW" | jq -c '
  (.data.repository.projectsV2.nodes // [])
  | map({
      id, number, title, url,
      fields: ((.fields.nodes // [])
        | map(select(.id != null and .name != null))
        | map({
            id, name,
            data_type: (.dataType // ""),
            options: ((.options // []) | map({id, name}))
          }))
    })')

jq -nc \
  --arg owner "$OWNER" \
  --arg repo  "$NAME" \
  --arg otype "$OWNER_TYPE" \
  --argjson its "$ISSUE_TYPES" \
  --argjson pjs "$PROJECTS" '
  {
    ok: true,
    owner: $owner,
    repo: $repo,
    owner_type: $otype,
    issue_types: $its,
    projects: $pjs
  }'
