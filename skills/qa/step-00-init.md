---
step: 00-init
next_step: 01-collect
description: Parse args, resolve target tickets (status=in_review), load config, compute diff scope.
---

# step-00 — init

Bootstrap a `/qa` run. Targets one ticket or every `in_review` ticket in a
feature.

## Tasks

1. **Parse args**: `--resume`/`-r`, positional `<id>`, `--dry-run`,
   `--no-wireframe-check`, `--retrigger`, `--no-doc-update` (v0.2 — opt out
   of post-success `/snap:doc-update` auto-trigger).

2. **Resume short-circuit**:
   ```bash
   resume_json=$(bash skills/_shared/resume-state.sh next \
     --skill=qa --project-root="$PWD")
   ```

3. **Resolve target**:
   - **Empty positional** → AskUserQuestion enumerating tickets where
     `status="in_review"`.
   - **Ticket-shaped** → single-ticket mode.
   - **Feature-shaped** → multi-ticket mode (every `in_review` ticket).

4. **Require config + load**:
   ```bash
   [ -f "$PWD/snapship.config.json" ] || {
     echo "ERROR: snapship.config.json not found. Run /snap:init first." >&2
     exit 1
   }
   cfg=$(bash skills/_shared/load-config.sh --project-root="$PWD")
   qa_cycles_max=$(echo "$cfg" | jq '.qa.qa_cycles_max // 2')
   sev_thr=$(echo "$cfg" | jq -r '.qa.severity_threshold // "minor"')
   regression_enabled=$(echo "$cfg" | jq '.qa.regression.enabled // true')
   regression_scope=$(echo "$cfg" | jq -r '.qa.regression.scope // "impacted"')
   wireframe_enabled=$(echo "$cfg" | jq '.qa.wireframe_check.enabled // false')
   retrigger_default=$(echo "$cfg" | jq '.qa.retrigger_review // false')
   ```
   `--no-wireframe-check` forces `wireframe_enabled=false` regardless of config.
   `--retrigger` forces `retrigger=true` even if config says otherwise.
   `--no-doc-update` sets `$NO_DOC_UPDATE=true` (consumed by step-05 E3).

5. **Pre-flight**:
   - `git rev-parse --is-inside-work-tree` — abort if not a repo.
   - At least one targeted ticket has `commit_sha` (else: nothing to QA).
   - `code-review-graph` MCP reachable for `regression_scope=impacted`. Fall
     back to `tests-only` with a logged warning if unreachable.
   - `wireframe_enabled=true` → Playwright MCP reachable, else log warning and
     skip wireframe checks (but do not abort the run).

6. **Compute diff scope** for each target ticket:
   ```bash
   sha=$(jq -r --arg lid "$lid" \
     '.tickets[] | select(.local_id == $lid).commit_sha' \
     "$tickets_file")
   files=$(git diff-tree --no-commit-id --name-only -r "$sha")
   ```
   Cache `$files` per ticket — drives step-01 regression scoping and step-04
   reviewer fan-out.

7. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" --feature-id="$feature_id" \
     --skill=qa --step-num=00 --step-name=init --status=ok \
     --note="targets=$count regression=$regression_scope wireframe=$wireframe_enabled"
   ```

## Acceptance check

- `target_kind` set + `target_tickets[]` non-empty.
- `regression_scope` resolved (with fallback chain).
- Per-ticket `files[]` (the diff) cached.

## Next step

→ `step-01-collect.md`
