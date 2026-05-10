# Structure

## 1. Layout plugin repo

```
snapship-plugin/  (plugin repo)
├── .claude-plugin/
│   └── plugin.json                         # manifest CC (name, version, metadata)
├── .mcp.json                               # MCP servers bundlés (code-review-graph)
├── CHANGELOG.md
├── NOTICE
├── LICENSE
├── README.md
├── skills/                                 # → installé dans ~/.claude/skills/ ou .claude/skills/
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
│   │   ├── steps/
│   │   │   ├── step-00-init.md
│   │   │   ├── step-01-decompose.md
│   │   │   ├── step-02-enrich.md
│   │   │   ├── step-03-format.md
│   │   │   ├── step-04-review.md
│   │   │   ├── step-05-push.md
│   │   │   └── step-06-finish.md
│   │   └── templates/
│   │       ├── ticket-jira.md
│   │       ├── ticket-github.md
│   │       └── ticket-gitlab.md
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
│   │       ├── step-03-fix.md           # cycle dev fix (auto_apply_qa_feedback) + re-run
│   │       ├── step-04-retrigger.md     # opt-in: re-run 3 reviewers /develop sur diff post-QA
│   │       └── step-05-finish.md
│   │
│   └── _shared/
│       ├── load-config.sh                  # parse snapship.config.json + apply defaults/inheritance + validate schema
│       ├── setup-config.sh                 # auto-générer snapship.config.json (premier run)
│       ├── detect-platforms.sh             # detect MCP/CLI dispo (auth check au runtime)
│       ├── detect-test-commands.sh         # auto-detect testing commands
│       ├── tickets-adapter.sh              # CRUD tickets (route MCP|CLI selon config.tickets.platform)
│       ├── docs-adapter.sh                 # CRUD docs (route AFFiNE|Notion selon config.documentation.platform)
│       ├── frame0-helper.sh                # wrapper Frame0 MCP
│       ├── run-lifecycle-script.sh         # exec lifecycle_scripts custom (pre_/post_) — ≠ hooks CC natifs
│       ├── ask-or-default.sh               # wrapper AskUserQuestion: shortcircuit en mode -a vers default explicite
│       ├── apply-naming.sh                 # render branch/commit/feature_id selon naming.*
│       ├── check-mcp-required.sh           # validate ai.mcp_servers_required (fail) + mcp_servers_optional (warn) au startup
│       ├── telemetry.sh                    # append _shared/telemetry.log NDJSON (duration_ms, status, ticket_id)
│       ├── setup-product-dir.sh
│       ├── update-index.sh
│       ├── update-progress.sh
│       ├── templates/
│       │   ├── docs-defaults/              # templates docs partagés (push par /define + /wireframe)
│       │   │   ├── prd-global.md
│       │   │   ├── prd-feature.md
│       │   │   └── wireframes-gallery.md
│       │   ├── pr-default.md               # fallback PR body si repository.pr_template_path absent
│       │   ├── daemon.sh.tpl               # template loop daemon /develop
│       │   └── session-start-hook.sh.tpl   # opt-in SessionStart hook (pre-load config)
│       ├── schemas/                        # JSON Schema bundlés validation runtime
│       │   ├── config.schema.json          # snapship.config.json
│       │   ├── meta.schema.json            # features/{id}/meta.json
│       │   ├── tickets.schema.json         # features/{id}/tickets.json
│       │   └── domains.schema.json         # v0.2 — .claude/product/domains.json
│       ├── domains-state.sh                # v0.2 — CRUD domains.json (cache domain/journey ↔ page ID)
│       └── telemetry.log                   # NDJSON append-only (rotation > 10MB) — runtime, gitignored
│
└── agents/                                 # → ~/.claude/agents/ ou .claude/agents/ (paths CC officiels)
    ├── code-reviewer-technical.md          # review code propre + conventions repo + lint/style
    ├── code-reviewer-functional.md         # review AC ticket + match wireframes + scope conformance
    ├── code-reviewer-security.md           # review OWASP + secrets + injection + auth + deps
    └── code-reviewer-qa.md                 # interprète raw outputs (tests + structural diff) → severity + feedback
```

## 2. Stockage projet — `.claude/product/` (minimal)

AFFiNE/Notion = source primaire docs. Local = cache + progress uniquement. Config vit racine projet.

```
<project_root>/
├── snapship.config.json            # Config unifiée (étend defaults bundlés)
└── .claude/product/
    ├── index.md                    # Track features (état + page IDs)
    ├── domains.json                # v0.2 — cache domain + journey → page IDs (persistant)
    └── features/
        └── 01-feature-name/
            ├── meta.json           # v0.2 — prd.{page_id,url,path}, domains[], impacted_journeys[]
            ├── tickets.json        # Cache tickets (id plateforme, AC, status)
            ├── prd-feature.md      # PRD rendu local (avant push archive {prd_root}/{YYYY}/{MM-YYYY}/)
            ├── wireframes/
            │   ├── manifest.json   # mapping screen ↔ ticket_id ↔ frame0_page_id
            │   └── *.png           # exports Frame0 (uploadés vers gallery)
            └── progress.md         # Log decisions + learnings
```

**Disparu vs plan v1:**

- ❌ `PRD.md` global local → AFFiNE
- ❌ `features/*/PRD.md` local → AFFiNE
- ❌ `platform.json` (fusionné dans `snapship.config.json`)
- ❌ `affine.config.json` (fusionné dans `snapship.config.json`)
- ✅ `meta.json` ajouté (lien local ↔ docs platform)
- ✅ `snapship.config.json` racine projet (config unique)

## 3. État `index.md` (centralise progression)

```markdown
# Product Index

## Features

| feature_id        | Nom           | État       | AFFiNE              | Tickets            | Wireframes              | Dev  |
| ----------------- | ------------- | ---------- | ------------------- | ------------------ | ----------------------- | ---- |
| 01-auth           | Auth          | developed  | [PRD](affine://...) | 8 (JIRA AUTH-1..8) | [Gallery](affine://...) | 8/8  |
| 02-dashboard      | Dashboard     | wireframed | [PRD](affine://...) | 12                 | [Gallery](affine://...) | 0/12 |
| 03-notifications  | Notifications | defined    | [PRD](affine://...) | -                  | -                       | -    |

## Plateforme tickets
- Type: jira (via MCP atlassian)
- Project: PROJ
- Last sync: 2026-05-08T...

## AFFiNE
- Workspace: ws-abc123 ("Mon Produit")
- Root page: page-product-root
- Templates configurés: prd_global, prd_feature, wireframes_gallery
```

États possibles: `defined`, `ticketed`, `wireframed`, `developed`, `qa-validated`.

Update via `_shared/update-index.sh feature_id state`.
