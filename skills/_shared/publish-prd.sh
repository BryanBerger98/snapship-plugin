#!/usr/bin/env bash
# publish-prd.sh — shell-pure helpers for step-05 publish (T1 / Phase 17).
#
# step-05 was 417 lignes of mixed bash + retry-wrapped MCP calls. The MCP
# sequence now lives in `agents/snap-publisher.md` (sub-agent, MCP-capable).
# This helper centralises the **non-MCP** plumbing — skip checks, path
# compute, JSON brief building — so step-05 stays declarative.
#
# Subcommands:
#   prepare --project-root=PATH --manifest=PATH
#       stdout: JSON {fid, skip, story_name, priority, year, month_year,
#                     prd_staging, domains, impacted_journeys,
#                     domain_titles, journey_titles}
#       skip=true when .refs.prd.sync_status == "synced". The caller still
#       reads the JSON to log/telemetry then continues without invoking the
#       sub-agent.
#
#   build-agent-prompt --brief=JSON --platform=X --workspace-id=Y
#                      --functional-root=Z --prd-root=W --project-root=PWD
#       stdout: plain text prompt ready to feed the snap-publisher Agent.
#       The prompt is shell-pure (no MCP) and embeds the prepare brief as
#       the only contextual payload.
#
# Exit codes:
#   0 — ok
#   1 — runtime error (manifest missing, state missing, jq failure)
#   2 — usage error (missing flag, unknown subcommand)
#
# Notes:
#   - The skill resolves domain/journey titles from `.snap/.define-state.json`
#     (richer than the manifest, which only stores slug pairs). Helper does
#     the lookup once instead of repeating jq filters across multiple steps.
#   - No MCP call here. No remote writes. No `.snap/manifests/_taxonomy.json`
#     mutation — those live in the sub-agent.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage:
  publish-prd.sh prepare --project-root=PATH --manifest=PATH
  publish-prd.sh build-agent-prompt --brief=JSON --platform=X --workspace-id=Y \
                                    --functional-root=Z --prd-root=W \
                                    --project-root=PWD
USAGE
}

cmd_prepare() {
  local project_root="" manifest=""
  for arg in "$@"; do
    case "$arg" in
      --project-root=*) project_root="${arg#*=}" ;;
      --manifest=*)     manifest="${arg#*=}" ;;
      -h|--help)        usage; exit 0 ;;
      *) echo "ERROR: unknown flag: $arg" >&2; usage; exit 2 ;;
    esac
  done

  if [ -z "$project_root" ] || [ -z "$manifest" ]; then
    echo "ERROR: --project-root and --manifest are required" >&2
    usage
    exit 2
  fi
  if [ ! -f "$manifest" ]; then
    echo "ERROR: manifest not found: $manifest" >&2
    exit 1
  fi

  local state_file="${project_root}/.snap/.define-state.json"
  if [ ! -f "$state_file" ]; then
    echo "ERROR: define-state not found: $state_file" >&2
    exit 1
  fi

  local fid story_name priority prd_status
  fid=$(jq -r '.story_id' "$manifest")
  story_name=$(jq -r '.story_name // ""' "$manifest")
  priority=$(jq -r '.priority // ""' "$manifest")
  prd_status=$(jq -r '.refs.prd.sync_status // ""' "$manifest")

  if [ -z "$fid" ] || [ "$fid" = "null" ]; then
    echo "ERROR: manifest missing story_id: $manifest" >&2
    exit 1
  fi

  local skip="false"
  [ "$prd_status" = "synced" ] && skip="true"

  local year month_year
  year=$(date -u +%Y)
  month_year=$(date -u +%m-%Y)

  # PRD staging path — sync-push.sh staging-path resolves the canonical
  # location for {fid, kind=prd}. We delegate to keep one source of truth.
  local prd_staging
  prd_staging=$(bash "$(dirname "${BASH_SOURCE[0]}")/sync-push.sh" staging-path \
    --story-id="$fid" --kind=prd --project-root="$project_root" 2>/dev/null || true)

  local domains_json journeys_json domain_titles_json journey_titles_json
  domains_json=$(jq -c '.domains // []' "$manifest")
  journeys_json=$(jq -c '.impacted_journeys // []' "$manifest")

  # Resolve human titles from define-state (manifest only stores slugs).
  domain_titles_json=$(jq -c --arg fid "$fid" '
    [
      .features[] | select(.story_id == $fid)
      | .impacted_journeys[]
      | {domain: .domain, title: (.domain_title // .domain)}
    ] | unique_by(.domain)
  ' "$state_file")

  journey_titles_json=$(jq -c --arg fid "$fid" '
    [
      .features[] | select(.story_id == $fid)
      | .impacted_journeys[]
      | {
          domain: .domain,
          journey_slug: .journey_slug,
          title: (.journey_title // .journey_slug)
        }
    ]
  ' "$state_file")

  jq -nc \
    --arg fid "$fid" \
    --argjson skip "$skip" \
    --arg story_name "$story_name" \
    --arg priority "$priority" \
    --arg year "$year" \
    --arg month_year "$month_year" \
    --arg prd_staging "$prd_staging" \
    --argjson domains "$domains_json" \
    --argjson journeys "$journeys_json" \
    --argjson domain_titles "$domain_titles_json" \
    --argjson journey_titles "$journey_titles_json" \
    --arg prd_status "$prd_status" '
    {
      fid: $fid,
      skip: $skip,
      skip_reason: (if $skip then "refs.prd.sync_status=" + $prd_status else "" end),
      story_name: $story_name,
      priority: $priority,
      year: $year,
      month_year: $month_year,
      prd_staging: $prd_staging,
      domains: $domains,
      impacted_journeys: $journeys,
      domain_titles: $domain_titles,
      journey_titles: $journey_titles
    }'
}

cmd_build_agent_prompt() {
  local brief="" platform="" workspace_id=""
  local functional_root="" prd_root="" project_root=""
  for arg in "$@"; do
    case "$arg" in
      --brief=*)            brief="${arg#*=}" ;;
      --platform=*)         platform="${arg#*=}" ;;
      --workspace-id=*)     workspace_id="${arg#*=}" ;;
      --functional-root=*)  functional_root="${arg#*=}" ;;
      --prd-root=*)         prd_root="${arg#*=}" ;;
      --project-root=*)     project_root="${arg#*=}" ;;
      -h|--help)            usage; exit 0 ;;
      *) echo "ERROR: unknown flag: $arg" >&2; usage; exit 2 ;;
    esac
  done

  if [ -z "$brief" ] || [ -z "$platform" ] || [ -z "$prd_root" ] \
     || [ -z "$functional_root" ] || [ -z "$project_root" ]; then
    echo "ERROR: --brief --platform --functional-root --prd-root --project-root are required" >&2
    usage
    exit 2
  fi

  # Validate brief is JSON.
  if ! echo "$brief" | jq empty 2>/dev/null; then
    echo "ERROR: --brief must be valid JSON" >&2
    exit 2
  fi

  local fid
  fid=$(echo "$brief" | jq -r '.fid')

  cat <<PROMPT
You are snap-publisher. Publish the PRD for story \`${fid}\` to ${platform}.

# Brief (from skill)
\`\`\`json
${brief}
\`\`\`

# Resolved paths
- platform: ${platform}
- workspace_id: ${workspace_id}
- functional_root: ${functional_root}
- prd_root: ${prd_root}
- project_root: ${project_root}

# Sequence (idempotent — skip on existing refs)
1. \`create-page-tree\` under \`${prd_root}/{year}/{month_year}\` (idempotent).
2. \`create\` PRD page under the month parent. Title = \`story_name\`. Body = \`prd_staging\` file content.
3. \`set-page-tags\` on the PRD page with \`domains\`.
4. \`lookup-or-create-page\` for \`functional_root\` under workspace root.
5. For each \`domain_titles[]\` not in taxonomy : \`lookup-or-create-page\` under functional_root, then \`taxonomy-state.sh add-domain\`.
6. For each \`journey_titles[]\` not in taxonomy : \`lookup-or-create-page\` under that domain's page, then \`taxonomy-state.sh add-journey\`. New journey pages stay empty (\`/snap:doc-update\` populates).
7. \`sync-push.sh ack --kind=prd\` with the PRD url + page-id.
8. Validate the patched manifest with \`ajv\` against \`skills/_shared/schemas/manifest.schema.json\`.

# MCP usage
Each step calls \`bash skills/_shared/docs-adapter.sh --action=... --platform=${platform} ...\`. The adapter exits 10 with a descriptor (\`{platform, action, params}\`). Map the descriptor to the actual MCP tool for the active platform and invoke it. Pipe each MCP response through \`bash skills/_shared/check-mcp-response.sh JSON KEY\` to extract / validate. On transient failure (rate-limit, timeout, 5xx, network, server-error, 502/503/504), retry via \`bash skills/_shared/retry-policy.sh REASON ATTEMPT\` with exponential backoff. Non-retryable reasons abort immediately.

# Output
Return exactly one fenced \`\`\`json block with the schema documented in your system prompt.
PROMPT
}

if [ "$#" -eq 0 ]; then
  usage
  exit 2
fi

case "$1" in
  prepare)            shift; cmd_prepare "$@" ;;
  build-agent-prompt) shift; cmd_build_agent_prompt "$@" ;;
  -h|--help)          usage; exit 0 ;;
  *) echo "ERROR: unknown subcommand: $1" >&2; usage; exit 2 ;;
esac
