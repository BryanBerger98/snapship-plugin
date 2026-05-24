# Shared scripts `_shared/`

All scripts in `skills/_shared/`. Reusable across skills.

## detect-platforms.sh

```bash
# args: --section=tickets|documentation|wireframes|all
# Output JSON: { tickets: { platform, via, auth }, documentation: {...}, ... }
# 1. Read snap.config.json (via load-config.sh)
# 2. For each configured platform:
#    - MCP server active? (parse claude_desktop_config / .claude/settings.json)
#    - Otherwise CLI available? (which gh glab jira)
#    - Auth test: gh auth status / glab auth status / jira me
# 3. Cache session result (in-memory, no disk — config = source of truth)
# 4. Fail fast if platform configured but no via available
```

## frame0-helper.sh

```bash
# Verify MCP frame0-mcp-server active
# Wrapper for batch operations (chain create page + shapes)
```

## setup-snap-dir.sh

```bash
# Init .snap/ idempotently (manifests/, PRDs/, designs/, wireframes/, tickets/,
# queues/, .doc-import/cache/). Bootstrap _taxonomy.json + progress.json.
# --story-id + --story-name → also init manifests/{id}.manifest.json
```

## manifest-state.sh

```bash
# Subcommands:
#   patch-from-define-state --project-root=PATH --story-id=NN-slug
#     Read .snap/.define-state.json, extract feature fields for STORY_ID
#     (priority, domains, impacted_journeys, parent_epic_{id,title,pending}),
#     atomically patch .snap/manifests/{story_id}.manifest.json with
#     updated_at = UTC now. Empty optionals are skipped (no overwrite with "").
#
# Exit codes: 0 ok / 1 runtime (manifest missing, story_id not in state,
#             jq failure) / 2 usage (missing flag, unknown subcommand).
#
# Used by step-04-render to keep step files declarative and the jq plumbing
# testable in isolation (cf. tests/test-manifest-state.sh).
```

## publish-prd.sh

```bash
# Shell-pure helpers backing /snap:define step-05 publish (T1 / Phase 17).
# The MCP-driven sequence (create-page-tree → create PRD → set-page-tags →
# lookup-or-create functional_root + per-domain + per-journey → ack manifest)
# is delegated to agents/snap-publisher.md (subprocesses cannot invoke MCP).
# This helper keeps the non-MCP plumbing : skip-check + path/title compute +
# agent-prompt builder.
#
# Subcommands:
#   prepare --project-root=PATH --manifest=PATH
#     stdout JSON {fid, skip, skip_reason, story_name, priority, year,
#                  month_year, prd_staging, domains,
#                  impacted_journeys, domain_titles, journey_titles}.
#     skip=true ↔ manifest.refs.prd.sync_status == "synced".
#
#   build-agent-prompt --brief=JSON --platform=X --workspace-id=Y \
#                      --functional-root=Z --prd-root=W --project-root=PWD
#     stdout: plain-text prompt embedding the brief, resolved paths, and the
#     step-by-step MCP sequence. The skill feeds this prompt to the
#     snap-publisher sub-agent.
#
# Exit codes: 0 ok / 1 runtime (manifest/state missing, jq failure) /
#             2 usage (missing flag, invalid JSON brief).
#
# Tests: tests/test-publish-prd.sh
```

## progress.sh

```bash
# Subcommands (subcommand first, then --flags):
#   start  --skill=X --story-id=Y
#   step   --skill=X --story-id=Y --step-num=NN --step-name=NAME --status=STATUS [--note=...]
#   finish --skill=X --story-id=Y --status=ok|fail
#   resume --skill=X --story-id=Y   # stdout: NUM\tNAME\tSTATUS or empty
#   list                              # stdout: in_flight[] JSON
# Writes .snap/progress.json (gitignored).
```

## load-config.sh

```bash
# Parse snap.config.json + apply bundled defaults + inheritance rules
# Output: normalized JSON (all fields resolved) on stdout
# Cases:
#   - Config missing → returns defaults
#   - Section missing → fill with defaults (skill decides if blocking — see setup trigger)
#   - inherit → resolve (tickets.platform=inherit → repository.platform)
#   - testing.*_command missing → auto-detect (package.json scripts, Makefile, pyproject)
#   - naming.ticket_id_regex missing → pattern by platform
# JSON Schema validation:
#   - Reads `_shared/schemas/config.schema.json` (or `.snap/schemas/` if copied)
#   - Validates via `jq` + basic check OR `ajv-cli` if available
#   - Schema errors → exit 1 + field path + reason
# Warnings (stderr, non-blocking):
#   - tickets.platform != "jira" + tickets.jira.* set
#     → "tickets.jira section ignored on platform Y"
# Cache resolution in .snap/.config-resolved.json (invalidated when mtime changes)
```

## Setup trigger pattern (each skill step-00)

```
1. load-config.sh → cache resolution
2. For each required section (per Auto-discovery sections by step):
   - If section missing OR critical fields missing → block + launch:
     setup-config.sh --section=<name> --interactive
   - setup-config.sh:
     - AskUserQuestion interactive mapping for required fields
     - Auto-discovery sub-fields (workspace via MCP, templates via name heuristic)
     - Persist snap.config.json
     - Validate via load-config.sh schema
   - Skill resumes step-00 with complete config
3. If flag `-a` AND section missing → fail explicitly (no AskUserQuestion in autonomous mode)
```

## ask-or-default.sh

```bash
# AskUserQuestion wrapper: short-circuit in -a mode to explicit default.
# args:
#   --auto-mode=true|false      (state {auto_mode})
#   --question-id=<id>          (diagnostic label — e.g. "confirm-platform")
#   --question="<text>"         (AskUserQuestion tool text if interactive)
#   --options=<csv>             (possible options)
#   --default=<value>           (REQUIRED if auto-mode=true)
# Behavior:
#   - auto-mode=true  → echo "{default}" on stdout, exit 0
#   - auto-mode=true without default → exit 1 + msg "auto-mode without default: question-id={id}"
#   - auto-mode=false → exit 0 + signal skill to invoke native AskUserQuestion tool
#                       (the wrapper CANNOT call the tool itself — skill will orchestrate)
# Note: in interactive mode, the wrapper is a guard/validator. The tool call stays skill-side.
```

## setup-config.sh

```bash
# Auto-generate snap.config.json at project root
# 1. Parse .git/config → repository.platform (clone URLs deductible from `git remote`, not persisted)
# 2. Detect active MCP servers (affine, notion, frame0, atlassian, github, gitlab)
# 3. AskUserQuestion progressive per section:
#    - tickets: platform + url + (if JIRA: jira.project_key + jira.workflow_states/transitions)
#    - documentation: platform + workspace_id + root_page_id + templates mapping
#    - wireframes: confirm frame0 or skip
#    - testing: auto-detect commands + AskUserQuestion override
#    - naming: defaults branch_pattern/commit_pattern + AskUserQuestion override
#    - develop: review_cycles_max + severity_threshold + fail_strategy
#    - qa: qa_cycles_max + severity_threshold + retrigger_review
#    - defaults: lang (FR/EN)
# 4. Write snap.config.json
# Idempotent: if config exists, proposes update for incomplete sections
```

## detect-test-commands.sh

```bash
# Auto-detect testing/typecheck/lint/format commands
# Output JSON: { test_command, typecheck_command, lint_command, format_command }
# Heuristic:
#   - package.json scripts → "test", "typecheck", "lint", "format" (priority)
#   - pnpm-lock.yaml → "pnpm" prefix, yarn.lock → "yarn", other → "npm run"
#   - Cargo.toml → "cargo test", "cargo check", "cargo clippy", "cargo fmt"
#   - pyproject.toml → "pytest", "mypy", "ruff check", "ruff format"
#   - Makefile → "test", "lint", etc. targets if present
#   - Otherwise → null (skill prompts user)
```

## apply-naming.sh

```bash
# args: type (story_id|branch|commit), context_json
# Reads config.naming.* + renders template with context vars
# Supported vars:
#   - story_id: hardcoded NN-kebab — args: {nn} (number), {name} → kebab truncated to `story_slug_max_length`
#   - branch: {type}, {ticket_id}, {slug}
#   - commit: {type}, {scope}, {message}
# Automatic slugify (kebab-case, ASCII fold, truncation)
```

## check-mcp-required.sh

```bash
# args: skill_name [--extra=<csv>]
# Reads config.ai.mcp_servers_required (fail-fast) + mcp_servers_optional (warn)
# --extra=<csv> dynamically adds MCPs to the required check-list for this run
#   (e.g. /qa skill calls with --extra=playwright if wireframe_check.enabled=true)
# Verifies each MCP is active (parse claude_desktop_config / .claude/settings.json)
# Required missing → exit 1 + install instructions
# Optional missing → log warning + dependent features disabled (flag returned via stdout JSON)
# Output stdout: { available: [...], missing_required: [...], missing_optional: [...] }
# Called by each skill at step-00 before continuing
#
# Multiple name conflicts (e.g. 2 affine variants installed):
#   - Match regex pattern (`affine-mcp*` matches `affine-mcp-server` AND `affine-mcp-server-v2`)
#   - First-match deterministic (stable alphabetical order from JSON config)
#   - If N>1 matches → stderr warning: "Multiple MCP match 'affine-mcp*': [name1, name2]. Using: name1."
#   - User can force exact name in config (`mcp_servers_required: ["affine-mcp-server"]` strict)
```

## docs-adapter.sh (AFFiNE/Notion abstraction)

```bash
# Routes to MCP based on config.documentation.platform
# Actions (read):
#   - get <page_id>                        → markdown content
#   - search <query>
#   - lookup-page (--title) (--workspace-id|--parent-id)        → page_id|empty
# Actions (write):
#   - create <parent_id> <title> <md>      → page_id + url
#   - apply-template <tpl_id> <parent_id> <title> <vars_json> → page_id + url
#   - upload-blob <file_path>              → blob_id (for embedding images)
#   - update <page_id> <markdown>
#   - lookup-or-create-page (idempotent) → page_id (existing or new)
#   - update-page-content <page_id> <markdown>
#   - set-page-tags <page_id> <tags_json_array>
#   - create-page-tree <path=A/B/C> (--workspace-id|--parent-id)→ leaf page_id
# Implementations:
#   - affine: affine-mcp-server MCP calls
#   - notion: notion-mcp MCP calls (community)
# Mode: write actions emit an MCP descriptor (exit 10) + short-circuit on --dry-run.
```

### Response envelope contract

Every write action (`create`, `apply-template`, `lookup-or-create-page`,
`create-page-tree`, `update`, `update-page-content`, `set-page-tags`,
`upload-blob`) returns a JSON object on stdout. Success and failure share the
same channel — callers must inspect the envelope before consuming any field.

```json
{ "page_id": "<platform-id>", "url": "https://…" }   // success
{ "blob_id": "<id>" }                                  // upload-blob success
{ "error":   "<reason>" }                              // any failure (rate-limit, auth, conflict, …)
```

Validate via `check-mcp-response.sh JSON KEY` (see below). Never extract a
value directly with `jq -r '.page_id'` — `null` round-trips as the literal
string `"null"` and silently poisons downstream state (`refs.prd`,
`_taxonomy.json`).

## check-mcp-response.sh

```bash
# args: JSON KEY
# Validates an MCP response envelope before the caller consumes a field.
# Checks (in order):
#   1. JSON parses as an object       → else rc=1 + stderr "mcp: malformed-json"
#   2. No `.error` key in object      → else rc=1 + stderr "mcp: error: <reason>"
#   3. `.KEY` present + non-null +    → else rc=1 + stderr "mcp: missing <KEY>"
#      non-empty string                          or "mcp: empty <KEY>"
# Success: stdout = captured value, rc=0.
# Usage error (wrong arg count): rc=2.
#
# Typical use — combined with retry-policy.sh for transient failures
# (see retry-policy.sh section below for the full pattern). Standalone
# use (no retry) is also valid when the caller wants fail-fast semantics:
#   MCP_RESPONSE=$(bash skills/_shared/docs-adapter.sh --action=create …)
#   if ! PAGE_ID=$(bash skills/_shared/check-mcp-response.sh \
#        "$MCP_RESPONSE" page_id 2>/tmp/mcp.err); then
#     bash skills/_shared/sync-push.sh fail --kind=prd --story-id="$fid" \
#       --reason="$(cat /tmp/mcp.err)"
#     continue
#   fi
```

## retry-policy.sh

```bash
# args: REASON ATTEMPT
# Decide whether an MCP failure (as reported by check-mcp-response.sh) is
# retry-able, sleep the backoff if so, and signal retry vs abort to the
# caller. Pairs with check-mcp-response.sh — REASON is its stderr line,
# ATTEMPT is the caller-side counter (1-based, incremented before each try).
#
# Env:
#   SNAP_MCP_RETRY_MAX      max retries after the initial attempt (default 2)
#   SNAP_MCP_RETRY_BASE_MS  base backoff ms, doubled per attempt (default 500)
#
# Behaviour (in order):
#   1. Non-retryable reason → rc=1, stderr "retry-policy: non-retryable: …"
#   2. Retryable but exhausted (ATTEMPT > MAX) → rc=1, stderr
#      "retry-policy: exhausted (ATTEMPT/MAX): …"
#   3. Retryable + within budget → sleep BASE_MS * 2^(ATTEMPT-1) ms, rc=0,
#      stderr "retry-policy: retry ATTEMPT/MAX in Nms (reason: …)"
#
# Retryable reasons (case-insensitive substring): rate-limit, ratelimit,
# timeout, network, transient, server-error, 5xx, 502, 503, 504.
# Everything else (auth-fail, not-found, malformed-json, missing/empty <KEY>,
# schema-fail, …) aborts on the first failure with no backoff.
#
# Rationale — keep retry *policy* deterministic and testable while the
# *mechanism* (re-invoking MCP) stays in the calling step. Subprocesses
# cannot invoke MCP directly, so policy/mechanism must split.
```

### Reference pattern — retry-wrapped MCP call

Every MCP write in `/snap:define` step-05 (and any future MCP-bridging
caller) follows this loop. It combines `check-mcp-response.sh` (envelope
guard) and `retry-policy.sh` (transient-error backoff). Adapt the
`continue` depth to the surrounding loop nesting (1 = next iteration of the
retry-while loop; 2/3 = skip up to outer feature/manifest loops).

```bash
attempt=0
while :; do
  attempt=$((attempt + 1))
  MCP_RESPONSE=$(bash skills/_shared/docs-adapter.sh --action=create …)
  if VALUE=$(bash skills/_shared/check-mcp-response.sh \
       "$MCP_RESPONSE" page_id 2>/tmp/mcp.err); then
    break
  fi
  if ! bash skills/_shared/retry-policy.sh \
       "$(cat /tmp/mcp.err)" "$attempt" 2>/tmp/retry.err; then
    bash skills/_shared/sync-push.sh fail --kind=prd --story-id="$fid" \
      --project-root="$PWD" --reason="$(cat /tmp/retry.err)"
    bash skills/_shared/progress.sh step --project-root="$PWD" \
      --skill=define --story-id="$fid" --step-num=05 --step-name=publish \
      --status=fail
    continue 2   # skip the retry-while + outer feature/manifest loop
  fi
done

# Secondary keys on the SAME envelope (e.g. `url` after `page_id`) are
# checked post-loop without retry — the resource may already exist; a
# missing field is a malformed envelope, not a transient failure.
if ! URL=$(bash skills/_shared/check-mcp-response.sh \
     "$MCP_RESPONSE" url 2>/tmp/mcp.err); then
  bash skills/_shared/sync-push.sh fail --kind=prd --story-id="$fid" \
    --project-root="$PWD" --reason="$(cat /tmp/mcp.err)"
  continue
fi
```

## taxonomy-state.sh (domain/journey ↔ page IDs cache)

```bash
# CRUD .snap/manifests/_taxonomy.json (persistent, schema: domains.schema.json)
# Source of truth for IDs in idempotent lookup-or-create in /snap:define publish + /snap:doc-update.
# Subcommands:
#   - init                                              → write {} if missing
#   - add-domain SLUG TITLE PAGE_ID [URL]               → idempotent (preserves journeys)
#   - add-journey DOMAIN_SLUG JOURNEY_SLUG TITLE PAGE_ID [URL]
#   - get-domain SLUG                                   → JSON entry or empty
#   - get-journey DOMAIN_SLUG JOURNEY_SLUG              → JSON entry or empty
#   - list-domains | list-journeys [DOMAIN_SLUG]
#   - has-domain SLUG | has-journey DOMAIN_SLUG SLUG    → exit 0/1
#   - validate                                          → ajv against schema
```

## tickets-adapter.sh (GitHub/GitLab/JIRA abstraction)

```bash
# Routes to MCP > CLI based on config.tickets.platform
# Actions:
#   - create <ticket_json>                 → id + url
#   - get <id>                             → ticket_json
#   - update <id> <fields_json>
#   - comment <id> <text>                          (comments a ticket/issue)
#   - comment-pr --pr-id=N (--comment | --body-file=PATH) (github/gitlab only —
#                                                  jira returns not_supported exit 1)
#   - list <feature_query>                 → array
#   - list-prs --branch=<name>             → existing PR for the branch (idempotent push)
#   - update-pr / create-pr                → PR CRUD
#   - set-issue-type    --ticket-id --issue-type=NAME           (github only, v1.1+)
#   - add-to-project    --ticket-id --project-id=PVT_xxx        (github only, v1.1+; echoes item_id)
#   - set-project-field --item-id --project-id --field-id       (github only, v1.1+)
#                       (--option-id=OPT | --value=TEXT)
# Implementations:
#   - github: gh CLI or github MCP (native actions use `gh api graphql`)
#   - gitlab: glab CLI or gitlab MCP
#   - jira: jira CLI or atlassian MCP
# Non-github platforms get a `not_supported` exit 1 for the three native actions.
# --body-file: read into COMMENT_TEXT if --comment empty (useful for rendered review-thread).
```

## detect-github-fields.sh (v1.1+)

```bash
# Pure read GraphQL probe — discovers org-level Issue Types + Projects v2
# attached to a repo (with their single-select fields and options).
# args:
#   --project-root=PATH        (accepted for parity; helper has no need for it)
#   --repo=owner/name          (default: resolved via `gh repo view`)
# Stdout JSON shape:
#   { ok, owner, repo, owner_type, issue_types:[{id,name,description}],
#     projects:[{id, number, title, url, fields:[{id, name, data_type, options}]}] }
# Graceful: if the Issue Types feature is unavailable on the org, returns an
# empty `issue_types` array (no fatal). Same for Projects v2.
# Test hook: SNAP_GH_BIN (stub binary).
```

## apply-github-metadata.sh (v1.1+)

```bash
# Post-create orchestrator. Reads the story (stdin or --story-file) + the
# resolved config block at tickets.github.* and dispatches:
#   - story.type → set-issue-type   (via the mapping issue_types{user-story|bug|epic})
#   - project.id present → add-to-project, then for each of {priority,size,scope}
#     → set-project-field if a mapping exists in project.fields.
# args:
#   --ticket-id=N                  GitHub issue number freshly created (REQUIRED)
#   --story-file=PATH | -          Story JSON (REQUIRED; `-` reads stdin)
#   --project-root=PATH            (default: $PWD or $SNAP_PROJECT_ROOT)
#   --config-json=JSON             Pre-resolved config (skips load-config.sh)
#   --dry-run                      Forwards SNAP_DRY_RUN=true to the adapter
# Stdout JSON shape:
#   { ok, ticket_id, applied:{issue_type, project_item_id, fields},
#     residual_labels:[…], skipped_reasons:{issue_type, project} }
# Early opt-out: tickets.github.enabled=false → returns story labels verbatim
# as residual, no adapter calls.
# Residual labels: drop type:/priority:/scope:/size: prefixes; keep labels
# matching tickets.github.label_fallback_prefixes (default ["feature:"]).
```

## detect-repo-templates.sh

```bash
# Detects a repo-native template (.github/.gitlab). Output: absolute path on
# stdout, or nothing (exit 0) if no repo-native template matches.
# args:
#   --kind=ticket|pr           (REQUIRED)
#   --type=user-story|bug|epic (REQUIRED if kind=ticket)
#   --platform=github|gitlab|jira  (ticket) | github|gitlab (pr)
#   --project-root=PATH        (default: $PWD or $SNAP_PROJECT_ROOT)
# Scanned conventions (markdown only — .yml/.yaml forms are ignored):
#   ticket/github → .github/ISSUE_TEMPLATE/*.md, .github/ISSUE_TEMPLATE.md
#   ticket/gitlab → .gitlab/issue_templates/*.md
#   ticket/jira   → (none — JIRA has no repo-native convention)
#   pr/github     → .github/PULL_REQUEST_TEMPLATE.md (+ root, docs/, directory form)
#   pr/gitlab     → .gitlab/merge_request_templates/*.md
# Filename → type mapping: *bug*/*defect* → bug, *epic* → epic,
#   *story*/*feature* → user-story. PR directory form → prefers 'default.md'.
# Exit codes: 0 success (path found or not) | 1 invalid args
```

## resolve-template.sh

```bash
# Resolves a template: config override > repo-native > bundled.
# Output: JSON object on stdout → {"path":"...","source":"...","render_mode":"..."}
#   source      = config | repo-native | bundled
#   render_mode = mustache (config/bundled) | scaffold (repo-native)
# args:
#   --kind=ticket|pr|review-thread|aggregated-feedback (REQUIRED)
#   --type=user-story|bug|epic                          (REQUIRED if kind=ticket)
#   --platform=github|gitlab|jira|default               (REQUIRED for ticket / pr / review-thread;
#                                                        pr also accepts 'default')
#   --project-root=PATH                                 (default: $PWD or $SNAP_PROJECT_ROOT)
# Read: load-config.sh (--no-validate) → templates.<key> per kind.
#   ticket           → templates.tickets.<type>     (user_story|bug|epic)
#   pr               → templates.pr
#   review-thread    → templates.review_thread
#   aggregated-feedback → templates.aggregated_feedback
# Resolution (in order):
#   1. Non-null config override → relative from project-root, absolute as-is.
#      Missing file → exit 2. render_mode=mustache.
#   2. Repo-native via detect-repo-templates.sh (ticket/pr kinds only,
#      gated by templates.use_repo_native, default true). render_mode=scaffold.
#   3. Bundled `_shared/templates/...`. Missing bundled → exit 2. render_mode=mustache.
# Exit codes: 0 success | 1 invalid args | 2 file not found
```

## telemetry.sh

```bash
# Append NDJSON event to _shared/telemetry.log
# args: --skill=<name> --step=<id> --status=<ok|fail|skip|retry> --duration-ms=<n> [--ticket=<id>] [--cycle=<n>] [--severity=<level>]
# Line format: {"ts":"...","skill":"...","step":"...","duration_ms":...,"status":"...",...}
# Auto rotation > 10MB (renames to .1, keeps 2 files max)
# Gitignored
```
