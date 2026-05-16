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
# --feature-id + --feature-name → also init manifests/{id}.manifest.json
```

## progress.sh

```bash
# Subcommands (subcommand first, then --flags):
#   start  --skill=X --feature-id=Y
#   step   --skill=X --feature-id=Y --step-num=NN --step-name=NAME --status=STATUS [--note=...]
#   finish --skill=X --feature-id=Y --status=ok|fail
#   resume --skill=X --feature-id=Y   # stdout: NUM\tNAME\tSTATUS or empty
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
#   - lifecycle_scripts.<name> pointing to non-existent script → "script X invalid path"
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

## run-lifecycle-script.sh

```bash
# Execute a CUSTOM workflow lifecycle_script (≠ native Claude Code hook).
# args: script_name (pre_define|post_ticket|...), context_json
# Reads config.lifecycle_scripts.<script_name>
# If key missing OR null → silently skip
# If defined (string path) → exec script with context_json on stdin
# Capture exit code: non-zero = stop workflow (or warning if --no-fail-lifecycle)
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
# 1. Parse .git/config → repository.{http_url, ssh_url, platform}
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
# args: type (feature_id|branch|commit), context_json
# Reads config.naming.* + renders template with context vars
# Supported vars:
#   - feature_id: hardcoded NN-kebab — args: {nn} (number), {name} → kebab truncated to `feature_slug_max_length`
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
