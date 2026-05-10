---
step: 03-confirm
next_step: 04-restructure
description: User reviews proposed_structure; allows JSON edit before commit. Skipped in --auto mode.
---

# step-03 — confirm

User checkpoint before any AFFiNE write. Last chance to abort or fix mapping.

## Tasks

1. **Display proposal** (already printed at end of step-02). Re-print summary
   table here for reference.

2. **`--auto` short-circuit**: if `$AUTO == true`, skip prompt and accept the
   proposal as-is. Print "auto-accept" line to stderr and proceed.

3. **AskUserQuestion**: 4 options
   - **Accept** — proceed to restructure
   - **Edit JSON** — open `$EDITOR` on `.doc-import-proposal.json`, re-validate
     after save (sanity rules from step-02), loop back to this prompt
   - **Re-run analysis** — go back to step-02 (clear `.doc-import-proposal.json`
     and `.doc-import-cache/`, re-cluster). Useful if the user disagrees with the
     domain split entirely.
   - **Cancel** — abort skill, print "doc-import cancelled" to progress.md

4. **On Edit JSON**:
   ```bash
   ${EDITOR:-vi} .claude/product/.doc-import-proposal.json
   # Re-validate after save
   jq empty .claude/product/.doc-import-proposal.json \
     || { echo "ERROR: invalid JSON after edit" >&2; exit 1; }
   ```
   Then re-run sanity rules from step-02 task #5 (every `source_pages[]` exists
   in index, no double-mapping, slug regex). On rule violation, print errors and
   loop back to AskUserQuestion.

5. **On Re-run analysis**:
   ```bash
   trash .claude/product/.doc-import-proposal.json 2>/dev/null
   trash .claude/product/.doc-import-cache 2>/dev/null
   ```
   Set shell var `$JUMP_TO=02-analyze` and exit step.

6. **Final confirmation table** (before proceeding to step-04):
   ```
   About to:
     - Strategy: synthesize
     - Create 2 domain pages, 3 journey pages
     - Affect 8 source pages (synthesize → tag [snap-imported])
     - Skip 1 unmapped page
     - Backup: yes / no
     - Dry run: yes / no
   ```
   In dry-run, step-04 will simulate without writing to AFFiNE.

## Acceptance check

- User chose Accept (or `--auto`).
- `.doc-import-proposal.json` passes sanity rules.

## Next step

→ `step-04-restructure.md` (or back to step-02 if Re-run, or skill exit if Cancel).
