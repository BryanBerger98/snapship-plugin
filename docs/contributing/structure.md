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
│   │   └── steps/
│   │       ├── step-00-init.md
│   │       ├── step-01-decompose.md
│   │       ├── step-02-enrich.md
│   │       ├── step-03-format.md
│   │       ├── step-04-review.md
│   │       ├── step-05-push.md
│   │       └── step-06-finish.md
│   │   # Templates ticket vivent dans _shared/templates/tickets/{type}/{platform}.md
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
│       ├── setup-snap-dir.sh
│       ├── progress.sh
│       ├── resolve-template.sh              # résout override config > repo-native > bundlé → JSON {path, source, render_mode}
│       ├── detect-repo-templates.sh         # détecte les templates .github/.gitlab (issue/PR), markdown only
│       ├── render-template.sh               # rendu Mustache-subset {{var}} {{#list}} {{^missing}} {{!comment}} {{&unescaped}}
│       ├── templates/
│       │   ├── tickets/                     # par type + plateforme
│       │   │   ├── user-story/
│       │   │   │   ├── github.md
│       │   │   │   ├── gitlab.md
│       │   │   │   └── jira.md
│       │   │   ├── bug/{github,gitlab,jira}.md
│       │   │   └── epic/{github,gitlab,jira}.md
│       │   ├── pr/                          # par plateforme + 'default' fallback
│       │   │   ├── github.md
│       │   │   ├── gitlab.md
│       │   │   └── default.md
│       │   ├── review-thread/               # commentaire posté sur PR/MR/JIRA ticket
│       │   │   └── {github,gitlab,jira}.md
│       │   ├── aggregated-feedback.md       # blob interne (review feedback → dev fix-loop)
│       │   ├── docs-defaults/               # templates docs partagés (push par /define + /wireframe)
│       │   │   ├── prd-feature.md
│       │   │   └── wireframes-gallery.md
│       │   ├── daemon.sh.tpl                # template loop daemon /develop
│       │   ├── develop-daemon.sh.tpl
│       │   └── session-start-hook.sh.tpl    # opt-in SessionStart hook (pre-load config)
│       ├── schemas/                        # JSON Schema bundlés validation runtime
│       │   ├── config.schema.json          # snapship.config.json
│       │   ├── manifest.schema.json            # manifests/{id}.manifest.json
│       │   ├── tickets.schema.json         # features/{id}/tickets.json
│       │   └── domains.schema.json         # v0.2 — .snap/manifests/_taxonomy.json
│       ├── taxonomy-state.sh                # v0.2 — CRUD _taxonomy.json (cache domain/journey ↔ page ID)
│       └── telemetry.log                   # NDJSON append-only (rotation > 10MB) — runtime, gitignored
│
└── agents/                                 # bundlés dans le plugin (préfixés `snap-` pour éviter collision avec project agents)
    ├── snap-code-reviewer-technical.md     # review code propre + conventions repo + lint/style
    ├── snap-code-reviewer-functional.md    # review AC ticket + match wireframes + scope conformance
    ├── snap-code-reviewer-security.md      # review OWASP + secrets + injection + auth + deps
    ├── snap-code-reviewer-qa.md            # interprète raw outputs (tests + structural diff) → severity + feedback
    └── snap-developer.md                   # applique aggregated feedback (write tools)
```

## 2. Stockage projet — `.snap/` (minimal)

AFFiNE/Notion = source primaire docs. Local = cache + progress uniquement. Config vit racine projet.

```
<project_root>/
├── snapship.config.json            # Config unifiée (étend defaults bundlés)
└── .snap/
    ├── index.md                    # Track features (état + page IDs)
    ├── _taxonomy.json                # v0.2 — cache domain + journey → page IDs (persistant)
    └── features/
        └── 01-feature-name/
            ├── manifest.json           # v0.2 — prd.{page_id,url,path}, domains[], impacted_journeys[]
            ├── tickets.json        # Cache tickets (id plateforme, AC, status)
            ├── prd-feature.md      # PRD rendu local (avant push archive {prd_root}/{YYYY}/{MM-YYYY}/)
            ├── wireframes/
            │   ├── manifest.json   # mapping screen ↔ ticket_id ↔ frame0_page_id
            │   └── *.png           # exports Frame0 (uploadés vers gallery)
            └── progress.json         # Log decisions + learnings
```

**Disparu vs plan v1:**

- ❌ `PRD.md` global local → AFFiNE
- ❌ `features/*/PRD.md` local → AFFiNE
- ❌ `platform.json` (fusionné dans `snapship.config.json`)
- ❌ `affine.config.json` (fusionné dans `snapship.config.json`)
- ✅ `manifest.json` ajouté (lien local ↔ docs platform)
- ✅ `snapship.config.json` racine projet (config unique)

## 3. État (centralisé via `manifests/_taxonomy.json` + per-feature manifests)

Le tableau d'index `index.md` v0.6.0 est supprimé. La progression vit dans :
- `.snap/manifests/{feature_id}.manifest.json` — `state`, `refs.{prd,wireframes_gallery,design_gallery}`, `tickets_count`, `lang`
- `.snap/manifests/_taxonomy.json` — workspace, domains, journeys
- `.snap/progress.json` — runs in-flight (gitignored)

États possibles: `defined`, `ticketed`, `wireframed`, `designed`, `developed`, `qa-validated`, `shipped`.

Update via `jq` patch atomique sur le manifest (skills écrivent eux-mêmes — pas de helper dédié).
