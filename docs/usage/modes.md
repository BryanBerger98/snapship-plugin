# Modes & flags

## `-a` (autonomous) mode — `ask-or-default.sh` wrapper

The native `AskUserQuestion` tool has no documented support for headless auto-bypass. Solution: a helper wrapper that short-circuits BEFORE the tool call.

**Pattern:** instead of calling `AskUserQuestion` directly, the skill calls `_shared/ask-or-default.sh`:

```bash
ask-or-default.sh \
  --auto-mode={auto_mode} \
  --question-id="confirm-platform" \
  --default="github" \
  --question="Which tickets platform?" \
  --options="github,gitlab,jira"
```

Behavior:

- If `--auto-mode=true` → output `{default}` on stdout, exit 0 (skip prompt)
- If `--auto-mode=false` → delegates to `AskUserQuestion` (skill orchestrates tool call)
- If `--auto-mode=true` AND `--default` absent → explicit fail (`auto-mode without default: question-id={id}`)

**Resolution of `{auto_mode}`:** each skill's step-00 reads `defaults.auto_mode`
from the resolved config (default `false`); the per-run flag `-a` / `--auto`
overrides it to `true`. The resolved value is what gets passed as
`--auto-mode=` to every `ask-or-default.sh` call.

**Benefit:** clean separation between machine-readable default and UI label. No fragile parsing of "(Recommended)".

**Skill responsibility:** define an explicit `default` per question to support `-a`. If a question is genuinely ambiguous without a sane default → don't pass it in autonomous mode (fail-fast guides user).

## Usage & cost monitoring

**Economy mode** (`defaults.economy_mode=true` or flag `-e`) — reduces parallelism + cycles:

- **Parallelism:** `ai.max_parallel_agents` forced to `1` (config override)
- **Review cycle:** `develop.review_cycles_max` forced to `1`
- **QA cycle:** `qa.qa_cycles_max` forced to `1`
- Rest of config unchanged (testing, naming, templates)

Note: economy does NOT swap the model (CC does not support cross-subagents runtime swap — `model:` frozen in frontmatter). To reduce global model cost: user runs `/model haiku` or `/effort low`.

CLI override `--economy=false` disables it even if config says `true`.

**Recommended native CC commands (monitoring):**

| Command    | Usage                                                             |
| ---------- | ----------------------------------------------------------------- |
| `/usage`   | Tokens consumed in current session + breakdown by model/tool      |
| `/cost`    | Estimated $ cost for the session                                  |
| `rtk gain` | If RTK installed — token savings via CLI proxy                    |

Each skill's step-finish suggests: "Check `/usage` or `/cost` post-run to track consumption. Iterate on `develop.review_cycles_max` or `--economy` if too costly."

**Local telemetry `_shared/telemetry.log`** (NDJSON append-only):

Each step-XX calls `telemetry.sh` start + end:

```
{"ts":"2026-05-09T10:00:00Z","skill":"develop","step":"step-03a:execute","duration_ms":12340,"status":"ok","ticket_id":"PROJ-12","cycle":1}
```

Fields: `ts | skill | step | duration_ms | status | ticket_id? | cycle? | severity?`. No PII. Automatic rotation > 10MB (rename `.1`, keep 2 files max). Gitignored. Used for plan v2 iteration (identify slow steps, frequent cycles, retries).

## Resume mode — unified pattern

Each skill, step-00:

```
If {resume_id} set:
  1. ls .snap/manifests/ | grep ^{resume_id}
  2. If match: read manifest.json, tickets.json, wireframes/manifest.json, progress.json
  3. (Optional) fetch PRD docs via manifest.json.prd.page_id if product context required
  4. Determine last completed step (parse progress.json)
  5. Load next step
  6. Otherwise: list available features, AskUserQuestion
```

## Strict `progress.json` format

Append-only file per feature. Each line = 1 timestamped event. Line-based regex parser, not semantic markdown.

**Header (created on the feature's first `/define`):**

```markdown
# Progress — {story_id}

started: {ISO-8601 UTC}
```

**Events (1 line = 1 event):**

```
{ISO-8601 UTC} | {skill} | {step} | {status} | {key=value;key=value} | {note}
```

| Field        | Format                                               | Example                          |
| ------------ | ---------------------------------------------------- | -------------------------------- |
| timestamp    | `YYYY-MM-DDTHH:MM:SSZ`                               | `2026-05-09T14:32:11Z`           |
| skill        | `define\|ticket\|wireframe\|develop\|qa`             | `develop`                        |
| step         | step-id (`step-XX-name` or sub-step `analyze`/`plan`)| `step-03a-standalone:execute`    |
| status       | `start\|ok\|fail\|skip\|retry`                       | `ok`                             |
| metadata     | `key=value;key=value` (URL-encoded, empty = `-`)     | `ticket=PROJ-12;cycle=2`         |
| note         | freetext (1 line, no pipe — escape `\|`)             | `severity=minor; AC 3/4 checked` |

**Full example:**

```
# Progress — 01-auth

started: 2026-05-09T10:00:00Z

2026-05-09T10:00:05Z | define | step-02-vision | ok | - | vision validated by user
2026-05-09T10:15:22Z | ticket | step-03-format | ok | count=4 | 4 draft tickets
2026-05-09T11:02:14Z | develop | step-03a-standalone:analyze | start | ticket=PROJ-12 | -
2026-05-09T11:08:33Z | develop | step-03a-standalone:execute | ok | ticket=PROJ-12 | files=3
2026-05-09T11:09:01Z | develop | step-03a-standalone:review | retry | ticket=PROJ-12;cycle=1 | sec=major
2026-05-09T11:14:50Z | develop | step-03a-standalone:review | ok | ticket=PROJ-12;cycle=2 | all<minor
2026-05-09T11:32:00Z | qa | step-01-collect | fail | ticket=PROJ-12 | regression: 1 fail (login_test)
```

**Parser rules:**

- Resume looks for the last event with status `ok` or `skip` → resumes at next step
- `retry` does not advance the pointer, indicates iteration
- `fail` not followed by `retry`/`ok` → state blocked, resume re-prompts user
- Flaky detection (`/qa`): groups events by `(skill, step, ticket)` over a 7-day window, count `fail` → `ok` with no code change between them = flaky candidate (see Flaky detection)

## Flaky detection heuristic (`/qa` step-02-interpret)

The `code-reviewer-qa` subagent receives raw output + `progress.json` extract (events `qa` for same feature/ticket within 7-day window). Logic:

```
flaky_score = 0
events = filter(progress, skill=qa, ticket={current}, last_7d)
groups = groupby(events, (step, test_name))

for each group:
  fails = count(status=fail)
  oks   = count(status=ok)
  if fails ≥ 1 AND oks ≥ 1 AND no commit between fail→ok for the same test:
    flaky_score += 1
    add test_name → flaky_list
```

**Commit-between heuristic:** check `git log --oneline {ts_fail}..{ts_ok}` against test + impl files (via `code-review-graph` `tests_for`). 0 commits modifying those files → likely flaky.

**Subagent output:**

```json
{
  "severity": "minor",
  "feedback_md": "...",
  "flaky_candidates": ["login_test", "checkout_e2e"],
  "stable_failures": ["payment_validate_test"]
}
```

`flaky_candidates` → severity downgraded `major→minor`, `feedback_md` recommends quarantine + investigate.
`stable_failures` → severity preserved, fix required before exiting the cycle.

## `--dry-run` global (preview without write calls)

All skills accept `--dry-run`:

- Adapters (`tickets-adapter.sh`, `docs-adapter.sh`, `frame0-helper.sh`) check the `{dry_run}` env var:
  - Read ops (fetch tickets, list pages) → run normally (read-only safe)
  - Write ops (create ticket, push page, comment, update status, push commits, create PR) → log to stdout `[DRY-RUN] would: <action> <args>`, skip exec
- Git ops: `git commit` skipped, `git push` skipped — log the diff that would have been committed
- AskUserQuestion → runs normally (user input is not a prod side-effect)
- Telemetry → logs with `"dry_run": true` flag
- step-finish displays summary: "Dry-run complete. N actions skipped: [...]. Re-run without --dry-run to apply."

Combinable with `-a` autonomous: skill runs end-to-end with defaults, exposes full plan without touching prod.

## SessionStart hook opt-in (pre-load config)

Optional for users frequently working in a snap project.

**Setup:** copy plugin template to a user location, then add to `~/.claude/settings.json` or project's `.claude/settings.json`:

```bash
# 1. Copy template (renamed without .tpl) to user-controlled location
cp ~/.claude/skills/_shared/templates/session-start-hook.sh.tpl \
   ~/.claude/lifecycle_scripts/session-start-hook.sh
chmod +x ~/.claude/lifecycle_scripts/session-start-hook.sh
```

```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "bash ~/.claude/lifecycle_scripts/session-start-hook.sh"
    }]
  }
}
```

> The `.tpl` stays read-only in the plugin (updated by plugin updates). User edits the copy without risk of overwrite.

**Template `session-start-hook.sh.tpl`:**

```bash
#!/usr/bin/env bash
# Pre-load snap context if current project has config
CONFIG=".snap/snap.config.json"
[ -f "$CONFIG" ] || exit 0

# Output additionalContext via JSON output (CC SessionStart format)
RESOLVED=$(bash ~/.claude/skills/_shared/load-config.sh 2>/dev/null) || exit 0
PLATFORM=$(echo "$RESOLVED" | jq -r '.tickets.platform')
DOCS=$(echo "$RESOLVED" | jq -r '.documentation.platform')

cat <<EOF
{
  "additionalContext": "snap active. Tickets: $PLATFORM. Docs: $DOCS. Skills: /define /ticket /wireframe /develop /qa."
}
EOF
```

**Benefit:** skills access context without re-parsing at each step-00 (`.config-resolved.json` cache remains the runtime source of truth). User controls activation — no automatic settings.json patch.
