# Structure

## 1. Plugin repo layout

```
snapship-plugin/  (plugin repo)
├── .claude-plugin/
│   └── plugin.json                         # CC manifest (name, version, metadata)
├── .mcp.json                               # bundled MCP servers (code-review-graph)
├── CHANGELOG.md
├── NOTICE
├── LICENSE
├── README.md
├── skills/                                 # → installed into ~/.claude/skills/ or .claude/skills/
│   ├── init/                               # /snap:init — bootstrap workspace (config + scaffold)
│   │   ├── SKILL.md
│   │   └── steps/
│   │       ├── step-00-detect.md
│   │       └── step-01-write.md
│   │
│   ├── define/
│   │   ├── SKILL.md
│   │   ├── steps/
│   │   │   ├── step-00-init.md
│   │   │   ├── step-01-discover.md
│   │   │   ├── step-02-vision.md
│   │   │   ├── step-03-features.md
│   │   │   ├── step-04-write-prd.md
│   │   │   └── step-05-finish.md
│   │   └── templates/
│   │       ├── PRD-global.md
│   │       ├── PRD-feature.md
│   │       └── index.md
│   │
│   ├── ticket/
│   │   ├── SKILL.md
│   │   └── steps/
│   │       ├── step-00-init.md
│   │       ├── step-01-decompose.md
│   │       ├── step-02-enrich.md
│   │       ├── step-03-format.md
│   │       ├── step-04-review.md
│   │       ├── step-05-push.md
│   │       └── step-06-finish.md
│   │   # Ticket templates live in _shared/templates/tickets/{type}/{platform}.md
│   │
│   ├── wireframe/
│   │   ├── SKILL.md
│   │   └── steps/
│   │       ├── step-00-init.md
│   │       ├── step-01-screens.md
│   │       ├── step-02-design.md
│   │       ├── step-03-link.md
│   │       └── step-04-finish.md
│   │
│   ├── develop/
│   │   ├── SKILL.md
│   │   ├── steps/
│   │   │   ├── step-00-init.md
│   │   │   ├── step-01-fetch.md
│   │   │   ├── step-02-prepare.md
│   │   │   ├── step-03a-standalone.md
│   │   │   ├── step-03b-loop-session.md
│   │   │   ├── step-03c-loop-daemon.md
│   │   │   ├── step-04-sync.md
│   │   │   └── step-05-finish.md
│   │   └── templates/
│   │       └── daemon.sh.tpl
│   │
│   ├── qa/
│   │   ├── SKILL.md
│   │   └── steps/
│   │       ├── step-00-init.md
│   │       ├── step-01-collect.md       # run regression (scope) + wireframe diff (Playwright opt)
│   │       ├── step-02-interpret.md     # spawn code-reviewer-qa subagent → severity + feedback_md
│   │       ├── step-03-fix.md           # dev fix cycle (auto_apply_qa_feedback) + re-run
│   │       ├── step-04-retrigger.md     # opt-in: re-run 3 reviewers /develop on post-QA diff
│   │       └── step-05-finish.md
│   │
│   └── _shared/
│       ├── load-config.sh                  # parse snapship.config.json + apply defaults/inheritance + validate schema
│       ├── setup-config.sh                 # auto-generate snapship.config.json (first run)
│       ├── detect-platforms.sh             # detect available MCP/CLI (auth check at runtime)
│       ├── detect-test-commands.sh         # auto-detect testing commands
│       ├── tickets-adapter.sh              # ticket CRUD (route MCP|CLI based on config.tickets.platform)
│       ├── docs-adapter.sh                 # docs CRUD (route AFFiNE|Notion based on config.documentation.platform)
│       ├── frame0-helper.sh                # Frame0 MCP wrapper
│       ├── run-lifecycle-script.sh         # exec custom lifecycle_scripts (pre_/post_) — ≠ native CC hooks
│       ├── ask-or-default.sh               # AskUserQuestion wrapper: short-circuit in -a mode to explicit default
│       ├── apply-naming.sh                 # render branch/commit/feature_id based on naming.*
│       ├── check-mcp-required.sh           # validate ai.mcp_servers_required (fail) + mcp_servers_optional (warn) at startup
│       ├── telemetry.sh                    # append _shared/telemetry.log NDJSON (duration_ms, status, ticket_id)
│       ├── setup-snap-dir.sh
│       ├── progress.sh
│       ├── resolve-template.sh              # resolves config override > repo-native > bundled → JSON {path, source, render_mode}
│       ├── detect-repo-templates.sh         # detect .github/.gitlab templates (issue/PR), markdown only
│       ├── render-template.sh               # Mustache-subset rendering {{var}} {{#list}} {{^missing}} {{!comment}} {{&unescaped}}
│       ├── templates/
│       │   ├── tickets/                     # by type + platform
│       │   │   ├── user-story/
│       │   │   │   ├── github.md
│       │   │   │   ├── gitlab.md
│       │   │   │   └── jira.md
│       │   │   ├── bug/{github,gitlab,jira}.md
│       │   │   └── epic/{github,gitlab,jira}.md
│       │   ├── pr/                          # by platform + 'default' fallback
│       │   │   ├── github.md
│       │   │   ├── gitlab.md
│       │   │   └── default.md
│       │   ├── review-thread/               # comment posted on PR/MR/JIRA ticket
│       │   │   └── {github,gitlab,jira}.md
│       │   ├── aggregated-feedback.md       # internal blob (review feedback → dev fix-loop)
│       │   ├── docs-defaults/               # shared docs templates (pushed by /define + /wireframe)
│       │   │   ├── prd-feature.md
│       │   │   └── wireframes-gallery.md
│       │   ├── daemon.sh.tpl                # /develop loop daemon template
│       │   ├── develop-daemon.sh.tpl
│       │   └── session-start-hook.sh.tpl    # opt-in SessionStart hook (pre-load config)
│       ├── schemas/                        # bundled JSON Schemas for runtime validation
│       │   ├── config.schema.json          # snapship.config.json
│       │   ├── manifest.schema.json            # manifests/{id}.manifest.json
│       │   ├── tickets.schema.json         # features/{id}/tickets.json
│       │   └── domains.schema.json         # v0.2 — .snap/manifests/_taxonomy.json
│       ├── taxonomy-state.sh                # v0.2 — CRUD _taxonomy.json (cache domain/journey ↔ page ID)
│       └── telemetry.log                   # NDJSON append-only (rotation > 10MB) — runtime, gitignored
│
└── agents/                                 # bundled in the plugin (prefixed `snap-` to avoid collision with project agents)
    ├── snap-code-reviewer-technical.md     # clean code review + repo conventions + lint/style
    ├── snap-code-reviewer-functional.md    # ticket AC review + wireframe match + scope conformance
    ├── snap-code-reviewer-security.md      # OWASP review + secrets + injection + auth + deps
    ├── snap-code-reviewer-qa.md            # interprets raw outputs (tests + structural diff) → severity + feedback
    └── snap-developer.md                   # applies aggregated feedback (write tools)
```

## 2. Project storage — `.snap/` (minimal)

AFFiNE/Notion = primary docs source. Local = cache + progress only. Config lives at project root.

```
<project_root>/
├── snapship.config.json            # Unified config (extends bundled defaults)
└── .snap/
    ├── index.md                    # Track features (state + page IDs)
    ├── _taxonomy.json                # v0.2 — cache domain + journey → page IDs (persistent)
    └── features/
        └── 01-feature-name/
            ├── manifest.json           # v0.2 — prd.{page_id,url,path}, domains[], impacted_journeys[]
            ├── tickets.json        # Tickets cache (platform id, AC, status)
            ├── prd-feature.md      # Locally rendered PRD (before push to archive {prd_root}/{YYYY}/{MM-YYYY}/)
            ├── wireframes/
            │   ├── manifest.json   # mapping screen ↔ ticket_id ↔ frame0_page_id
            │   └── *.png           # Frame0 exports (uploaded to gallery)
            └── progress.json         # Decisions + learnings log
```

**Gone vs v1 plan:**

- ❌ Global local `PRD.md` → AFFiNE
- ❌ Local `features/*/PRD.md` → AFFiNE
- ❌ `platform.json` (merged into `snapship.config.json`)
- ❌ `affine.config.json` (merged into `snapship.config.json`)
- ✅ `manifest.json` added (local ↔ platform docs link)
- ✅ `snapship.config.json` at project root (single config)

## 3. State (centralized via `manifests/_taxonomy.json` + per-feature manifests)

The `index.md` index table from v0.6.0 is removed. Progression lives in:
- `.snap/manifests/{feature_id}.manifest.json` — `state`, `refs.{prd,wireframes_gallery,design_gallery}`, `tickets_count`, `lang`
- `.snap/manifests/_taxonomy.json` — workspace, domains, journeys
- `.snap/progress.json` — in-flight runs (gitignored)

Possible states: `defined`, `ticketed`, `wireframed`, `designed`, `developed`, `qa-validated`, `shipped`.

Update via atomic `jq` patch on the manifest (skills write directly — no dedicated helper).
