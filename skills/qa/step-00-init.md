---
step: 00-init
next_step: 01-collect
description: Parse args, fetch live ticket (tracker = source), apply story_type filters, load config, compute diff scope. v1.2 — ticket-first, no local cache.
---

# step-00 — init

Bootstrap a `/qa` run. Targets one ticket via `--ticket=<platform_id>` (the
v1.2 contract — same as `/develop`). Tracker is the single source of truth :
no `.snap/tickets/` reads.

## Tasks

1. **Parse args**: `--ticket=<platform_id>` mandatory (regex per-platform —
   `gh|gl: ^#?[0-9]+$`, `jira|linear: ^[A-Z][A-Z0-9_]+-[0-9]+$`),
   `--resume`/`-r`, `--dry-run`, `--no-wireframe-check`, `--retrigger`,
   `--no-doc-update` (opt out of post-success `/snap:doc-update`).

   Reject empty `--ticket=` with explicit message — no enumeration mode in
   v1.2 (single-ticket scope, like `/develop`).

2. **Resume short-circuit**:
   ```bash
   resume_json=$(bash skills/_shared/progress.sh resume \
     --project-root="$PWD" --skill=qa)
   ```

3. **Init ephemeral runtime + fetch live ticket** :
   ```bash
   subject_id="$PLATFORM_ID"
   bash skills/_shared/cache-runtime.sh init \
     --project-root="$PWD" --subject-id="$subject_id"
   trap 'bash skills/_shared/cache-runtime.sh destroy --subject-id="$subject_id"' EXIT

   TICKET_JSON=$(bash skills/_shared/tickets-adapter.sh get-ticket \
     --platform="$platform" --id="$PLATFORM_ID" \
     --config-json="$CONFIG_JSON")
   echo "$TICKET_JSON" > ".snap/.runtime/${subject_id}/ticket.json"

   story_type=$(jq -r '.story_type // "user-story"' <<<"$TICKET_JSON")
   commit_sha=$(jq -r '.commit_sha // ""' <<<"$TICKET_JSON")
   ```

   `--keep-runtime` flag preserves the runtime dir for inspection.

4. **story_type filter (double-safety)** :

   `/develop` already refuses Epic (step-01 exit 20). `/qa` enforces again :

   | story_type | wireframe_check | design_check | regression |
   |------------|-----------------|--------------|------------|
   | `user-story` | enabled (config) | enabled (config) | full |
   | `task` | **skipped** (no user-facing artefact) | **skipped** | full |
   | `bug` | **skipped** (regression scope = code) | conditional¹ | full |
   | `epic` | **rejected** — exit 20 |||

   ¹ Bug visual : `design_check` kept only if ticket has label `visual` /
   `ui-bug` OR `wireframe_url` set. Otherwise skipped.

   ```bash
   case "$story_type" in
     epic)
       echo "ERROR: /qa cannot validate an Epic — Epics aggregate child US/Task." >&2
       echo "       Hint: run /qa --ticket=<child-id> on each child instead." >&2
       exit 20
       ;;
     task)
       wireframe_enabled=false
       design_check_enabled=false
       ;;
     bug)
       wireframe_enabled=false
       has_visual=$(jq -r '
         (.labels // []) | map(ascii_downcase)
         | (index("visual") != null) or (index("ui-bug") != null)
       ' <<<"$TICKET_JSON")
       has_wf_url=$(jq -r '(.wireframe_url // "") != ""' <<<"$TICKET_JSON")
       if [ "$has_visual" = "true" ] || [ "$has_wf_url" = "true" ]; then
         design_check_enabled=true
       else
         design_check_enabled=false
       fi
       ;;
     user-story|*)
       # default: respect config flags as-is
       ;;
   esac
   ```

5. **Require config + load**:
   ```bash
   [ -f "$PWD/snap.config.json" ] || {
     echo "ERROR: snap.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   CONFIG_JSON=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   qa_cycles_max=$(jq '.qa.qa_cycles_max // 2' <<<"$CONFIG_JSON")
   sev_thr=$(jq -r '.qa.severity_threshold // "minor"' <<<"$CONFIG_JSON")
   regression_enabled=$(jq '.qa.regression.enabled // true' <<<"$CONFIG_JSON")
   regression_scope=$(jq -r '.qa.regression.scope // "impacted"' <<<"$CONFIG_JSON")
   wireframe_enabled=$(jq '.qa.wireframe_check.enabled // false' <<<"$CONFIG_JSON")
   retrigger_default=$(jq '.qa.retrigger_review // false' <<<"$CONFIG_JSON")
   ```
   `--no-wireframe-check` forces `wireframe_enabled=false` regardless of config.
   `--retrigger` forces `retrigger=true` even if config says otherwise.
   `--no-doc-update` sets `$NO_DOC_UPDATE=true` (consumed by step-05 E3).

6. **Pre-flight**:
   - `git rev-parse --is-inside-work-tree` — abort if not a repo.
   - Targeted ticket has `commit_sha` (else: nothing to QA, exit clean).
   - `code-review-graph` MCP reachable for `regression_scope=impacted`. Fall
     back to `tests-only` with a logged warning if unreachable.
   - `wireframe_enabled=true` → Playwright MCP reachable, else log warning and
     skip wireframe checks (but do not abort the run).

7. **Compute diff scope** :
   ```bash
   files=$(git diff-tree --no-commit-id --name-only -r "$commit_sha")
   ```
   Cache `$files` in `.snap/.runtime/${subject_id}/files.txt` — drives step-01
   regression scoping and step-04 reviewer fan-out.

8. **Telemetry + progress**:
   ```bash
   bash skills/_shared/telemetry.sh log \
     --project-root="$PWD" --skill=qa \
     --step-num=00 --step-name=init --status=ok \
     --extra="{\"story_type\":\"$story_type\",\"wireframe_enabled\":$wireframe_enabled,\"design_check_enabled\":${design_check_enabled:-$wireframe_enabled}}"

   bash skills/_shared/progress.sh step \
     --project-root="$PWD" --story-id="$PLATFORM_ID" \
     --skill=qa --step-num=00 --step-name=init --status=ok \
     --note="story_type=$story_type regression=$regression_scope wireframe=$wireframe_enabled"
   ```

## Acceptance check

- `--ticket=` parsed, regex-validated, ticket fetched from tracker.
- `story_type` extracted and filter applied (Epic refused with exit 20).
- `regression_scope` resolved (with fallback chain).
- `files[]` cached in runtime dir.

## Next step

→ `step-01-collect.md`
