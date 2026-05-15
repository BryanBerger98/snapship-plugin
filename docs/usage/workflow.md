# Detection & integration workflow

## Initial setup (first `/define` — config absent)

`_shared/setup-config.sh` auto-discovery:

```
1. Parse .git/config → repository.{platform, http_url, ssh_url, default_branch}
2. List active MCP servers (parse claude_desktop_config / .claude/settings.json)
   → look for: atlassian, github, gitlab, affine, notion, frame0
3. For each section required by the current skill:
   - If relevant MCP found → offer as option
   - Otherwise → offer available CLI (which gh/glab/jira)
   - AskUserQuestion choice + parameters
4. Per-section setup detail:
   - tickets: platform + url + (if JIRA: jira.project_key + jira.workflow_states/transitions)
   - documentation:
     · List AFFiNE/Notion workspaces via MCP → AskUserQuestion choice
     · List template pages (heuristic: name contains "Template") → mapping
     · Missing templates → AskUserQuestion "Create defaults now?"
       Yes: push from `templates/docs-defaults/{prd-feature,wireframes-gallery}.md`
       No: pages from scratch
     · `root_page_id` choice: existing page or create "Product"
   - wireframes: confirm frame0 or skip
   - testing: auto-detect commands + override
   - naming: branch_pattern/commit_pattern defaults + AskUserQuestion override
   - develop: review_cycles_max + severity_threshold + fail_strategy
   - qa: qa_cycles_max + severity_threshold + retrigger_review
   - defaults: lang (FR/EN)
5. AskUserQuestion confirm (shows preview)
6. Write `snapship.config.json` at root
```

Idempotent: if partial config exists, only proposes update for incomplete sections.

## Runtime check (config present) — `detect-platforms.sh`

**Source of truth = `snapship.config.json`.** No re-detection except auth check.

```
1. Read snapship.config.json (via load-config.sh)
2. For each configured platform:
   - MCP server active? (check MCP listing)
   - Otherwise CLI available? (which + auth check)
   - If nothing available → clear error with install/auth instructions
3. Cache result for session (in-memory, not disk)
```

**Auth check per platform:**

- `gh auth status` (exit 0 = ok)
- `glab auth status`
- `jira me` (jira-cli ankitpokhrel)
- AFFiNE/Notion MCP: try 1 read call, catch error

## Docs/tickets integration flows per skill

```
/define
  ├─ step-04: render per-feature PRD locally
  ├─ step-05: push PRD page archive `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (immutable, tagged with domains)
  │           + lookup-or-create domain + journey pages under `{functional_root}/`
  └─ manifest.json: { prd: {page_id, url, path}, domains[], impacted_journeys[] }
     _taxonomy.json: { <domain>: {domain_page_id, journeys: { <slug>: {page_id, url} }} }

/snap:doc-import
  └─ AI clusters existing doc pages → restructure (synthesize|copy|move)
     → one-shot populate _taxonomy.json

/snap:doc-update (auto post-QA if auto_update_on_qa_success)
  ├─ step-01: fetch PRD + current journey pages + git diff for the feature
  ├─ step-02: AI patch (mode=diff) or rewrite (mode=rewrite)
  └─ step-03: push update-page-content (PRD never touched)

/ticket
  ├─ step-00: reads feature PRD from docs platform (MCP fetch via manifest.json.prd.page_id)
  ├─ step-05 (push): PRD link added to ticket description
  └─ Optional: add ticket links in feature docs page ("Tickets" section)

/wireframe
  ├─ step-00: reads tickets cache + feature docs page
  ├─ step-03: creates "Wireframes Gallery" page as sub-page of feature PRD
  │           - uploads PNG via blob MCP
  │           - embeds images + ticket links + Frame0 links
  └─ Updates platform tickets with gallery link

/develop
  ├─ step-02: reads ticket + reads feature docs PRD → enriched context + creates branch
  │           (apply-naming.sh branch idempotent, skip if branch_mode=false)
  ├─ step-03a: 2 phases
  │  ├─ Phase 1 — Code: inline workflow analyze/plan/execute/validate
  │  └─ Phase 2 — Review cycle (max `review_cycles_max`):
  │              · 3 parallel reviewers (technical, functional, security)
  │              · per-type severity check vs `reviews.{type}.severity_threshold`
  │              · 1 dev agent applies {aggregated_feedback}
  │              · early stop if ALL types < threshold (first clean batch accepted)
  │  → 1 atomic commit per ticket (amend if Phase 2 fixes)
  └─ step-04: push commits + sync ticket + create PR/MR
              (template `templates.pr` user override > bundled `_shared/templates/pr/{platform}.md`)
              + post review-thread (PR comment rendered via `templates.review_thread`)

/qa  (separate skill — runtime validation)
  ├─ step-00: loads manifest.json + tickets.json + determines diff scope (ticket/feature commits)
  ├─ step-01-collect: raw outputs (regression scope=impacted via code-review-graph + wireframe via Playwright)
  ├─ step-02-interpret: spawns `code-reviewer-qa` subagent → severity + feedback_md
  ├─ step-03-fix: dev↔qa cycle (max `qa.qa_cycles_max`)
  │             · exit if regression=pass AND wireframe=pass AND severity < threshold
  │             · fixes amend atomic ticket commit
  └─ step-04-retrigger (opt-in `qa.retrigger_review=true` AND fixes applied):
              · re-run /develop 3 reviewers on post-QA diff (1 retrigger max)
```

## Error handling (MCP/CLI fail mid-workflow)

**Policy: fail-fast + resume.**

```
Any failed MCP/CLI call (timeout, auth, API error):
  1. Skill catches error, captures stack trace + step name
  2. Updates progress.json with:
     - timestamp, failed step, exact error
     - partial state (key variables, IDs created before fail)
  3. Displays clear message:
     - Likely cause (expired auth, MCP server down, rate limit)
     - Required user action (re-auth, restart MCP, wait)
     - Resume command: `/<skill> -r {feature_id}`
  4. Non-zero exit → workflow stops cleanly
```

**Idempotence:** each step must be re-runnable without duplication:

- `/snap:define`: before creating PRD page, check `manifest.json.prd.page_id` exists
- `/ticket`: before creating ticket, check if already pushed (cache `tickets.json`)
- `/wireframe`: checksum-based blob upload dedup
- `/develop`: idempotent branch checkout, diff-based commit message

**No auto-retry.** User decides after diagnosis.
