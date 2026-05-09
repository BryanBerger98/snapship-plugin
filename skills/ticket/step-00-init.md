---
step: 00-init
next_step: 01-load
description: Parse args, resolve feature_id, load resolved config, branch on resume.
---

# step-00 — init

Bootstrap a `/ticket` run for a single feature.

## Tasks

1. **Parse args**: `--resume`/`-r`, `--feature=PARTIAL`, `--platform=…`, `--max-stories=N`,
   `--dry-run`.

2. **Resume short-circuit**: if `--resume`, delegate to `resume-state.sh`:
   ```bash
   resume_json=$(bash skills/_shared/resume-state.sh next \
     --skill=ticket \
     --project-root="$PWD" \
     ${feature:+--feature="$feature"})
   rc=$?
   ```
   - `rc=0` → parse `next_step` + `feature_id`, jump to that step.
   - `rc=1` → no in-flight run; fall through to step-00 fresh.
   - `rc=2` → bad args; abort.

3. **Resolve `feature_id`**: if not passed and not resumed:
   - Single refined feature in `.claude/product/features/` → use it.
   - Multiple → `AskUserQuestion` with the list of `feature_id` options.
   - Zero → abort with "Run `/define` first".

   For partial matches (`--feature=auth`), reuse `resume-state.sh` matching logic by
   listing `features/` and applying the same precedence (exact → numeric prefix →
   slug prefix). Bail on ambiguity with the candidate list.

4. **Load config**:
   ```bash
   bash skills/_shared/load-config.sh --project-root="$PWD" > /tmp/cfg.json
   platform=$(jq -r '.tickets.platform' /tmp/cfg.json)
   ```
   `--platform=` arg overrides the resolved value.

5. **Pre-flight checks**:
   - Feature dir exists: `.claude/product/features/${feature_id}/`.
   - `prd-feature.md` exists in that dir (run `/define --feature=…` first if missing).
   - Tickets-adapter MCP / CLI requirements met:
     ```bash
     bash skills/_shared/check-mcp-required.sh --skill=ticket --project-root="$PWD"
     ```

6. **Append progress**:
   ```bash
   bash skills/_shared/update-progress.sh \
     --project-root="$PWD" \
     --feature-id="$feature_id" \
     --step-num=00 \
     --step-name=init \
     --status=ok \
     --skill=ticket
   ```

## Variables to record (in-context)

| Var | Source | Used by |
|-----|--------|---------|
| `feature_id` | arg / detection | step-01..06 |
| `platform` | config / arg | step-04 (template), step-05 (adapter) |
| `max_stories` | arg (default 12) | step-02 |
| `dry_run` | arg / env | step-05 |

## Acceptance check

- `feature_id` resolved.
- `prd-feature.md` exists for `feature_id`.
- `progress.md` has `ticket step-00 init — ok`.

## Next step

→ `step-01-load.md`
