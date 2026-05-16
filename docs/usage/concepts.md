# Documentation Architecture

Product documentation model. Separates the PRD (immutable archive of an
evolution) from the living functional doc (current spec of a user journey).

## Concepts

| Type | Cycle | Content | Versioning |
|------|-------|---------|------------|
| **PRD / Change request** | Short-term — 1 per evolution | What WILL change + why (deltas, AC, scope) | Archived immutably post-ship |
| **Functional doc (journey)** | Long-term — living | What the feature DOES today (flows, rules, contracts) | Updated on each ship via `/snap:doc-update` |
| **Domain page** | Long-term — living | Overview of a product domain, links to journeys | Updated only when new journeys are added |

No log of changes on the domain page (would avoid pages becoming massive
over cycles). History = via the PRD pages themselves (filterable in AFFiNE
by tag + date).

## AFFiNE hierarchy

```
{functional_root}/             e.g. "Product Docs"
└── {domain}/                   e.g. "auth"
    ├── (domain page = overview, links to journeys)
    ├── Login Flow              ← user journey page
    ├── Signup Flow
    └── Password Reset

{prd_root}/                     e.g. "Change Requests"
└── {YYYY}/
    └── {MM-YYYY}/
        └── {NN-story_slug}   ← PRD page (tags: impacted domains)
```

PRD path example: `Change Requests/2026/05-2026/01-simple-login-button`.

## Config schema additions

```json
{
  "documentation": {
    "platform": "affine | notion | none",
    "paths": {
      "functional_root": "Product Docs",
      "prd_root": "Change Requests"
    },
    "auto_update_mode": "diff | rewrite",
    "auto_update_on_qa_success": true
  }
}
```

| Field | Default | Role |
|-------|---------|------|
| `paths.functional_root` | `"Product Docs"` | Root page of the living functional doc |
| `paths.prd_root` | `"Change Requests"` | Root page of the PRD archive |
| `auto_update_mode` | `"diff"` | Post-ship journey update mode: `diff` (patch impacted sections) or `rewrite` (regenerate full) |
| `auto_update_on_qa_success` | `true` | Auto-trigger `/snap:doc-update` when `/snap:qa` validates |

## Local storage

### `.snap/manifests/_taxonomy.json` (new)

Cache mapping domains + journeys ↔ AFFiNE page IDs. Avoids re-lookup at
every skill run, suggests existing values at the next `/snap:define`.

```json
{
  "auth": {
    "domain_page_id": "abc-123",
    "domain_url": "https://...",
    "journeys": {
      "login-flow": {
        "title": "Login Flow",
        "page_id": "def-456",
        "url": "https://..."
      },
      "signup-flow": {
        "title": "Signup Flow",
        "page_id": "ghi-789",
        "url": "https://..."
      }
    }
  },
  "dashboard": {
    "domain_page_id": "...",
    "journeys": {
      "overview": { "title": "Overview", "page_id": "...", "url": "..." }
    }
  }
}
```

### feature `manifest.json` (revised)

```json
{
  "story_id": "01-simple-login-button",
  "story_name": "Simple login button",
  "state": "defined | in-progress | qa-validated",
  "domains": ["auth", "dashboard"],
  "impacted_journeys": [
    { "domain": "auth", "journey_slug": "login-flow" },
    { "domain": "dashboard", "journey_slug": "overview" }
  ],
  "prd": {
    "page_id": "...",
    "url": "...",
    "path": "Change Requests/2026/05-2026/01-simple-login-button"
  },
  "created_at": "2026-05-09T16:34:22Z",
  "updated_at": "2026-05-15T10:00:00Z"
}
```

Feature manifests reference the PRD via `prd.page_id`.

## Slugs vs titles

- **AFFiNE page title** = human ("Login Flow", "Signup Flow")
- **Internal slug** = kebab-case (`login-flow`) for cache + referencing

user_journey slug is free (no config enum). User enters title → slug
auto-generated (slugify), or user overrides slug explicitly.

## Revised `/snap:define` workflow

### step-03-features (modified)

For each feature, after collecting AC + scope, ask:

1. **Impacted domains** (multi-select + free input):
   - Suggest from `_taxonomy.json` (already known)
   - Allow adding new domain (title input + auto slug)

2. **Journeys impacted by domain**:
   - For each chosen domain: select existing journeys OR create new one
   - If new: ask for human title → auto slug

Persist in state file + later in manifest.json.

### step-05-publish (major refactor)

For each feature:

1. **Compute PRD path**:

   ```bash
   YEAR=$(date +%Y)
   MONTH_YEAR=$(date +%m-%Y)
   PRD_PATH="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}/${FEATURE_ID}"
   ```

2. **Create PRD page** (always new, no idempotence — unique feature per
   story_id):
   - Title: story_name
   - Tags: list of impacted domains
   - Body: rendered `prd-feature.md`
   - Parent: lookup-or-create `{prd_root}/{YYYY}/{MM-YYYY}` (recursive if absent)

3. **Lookup-or-create domain pages** (idempotent):
   - For each domain in `feature.domains`:
     - Lookup `{functional_root}/{domain}` in `_taxonomy.json`
     - If miss: create page → save `domain_page_id` in `_taxonomy.json`

4. **Lookup-or-create journey pages** (idempotent):
   - For each `(domain, journey_slug)` in `feature.impacted_journeys`:
     - Lookup in `_taxonomy.json[domain].journeys[journey_slug]`
     - If miss: create page under the domain page → save in `_taxonomy.json`
     - If new: page initialized empty (will be populated by the first
       post-ship `/snap:doc-update`)

5. **Save IDs**:
   - `feature.manifest.json`: `prd.page_id`, `prd.url`, `prd.path`
   - `_taxonomy.json`: new domain/journey entries

6. **NO modification**:
   - NO log entry on the domain page
   - NO direct journey → PRD link
   - PRD page will never be touched again after creation

## New `/snap:doc-update` skill

### Trigger

| Source | Condition |
|--------|-----------|
| Auto post-`/snap:qa` | `documentation.auto_update_on_qa_success: true` AND state transitions to `qa-validated` |
| Manual | `/snap:doc-update --feature=NN-slug` |

### Steps

```
skills/doc-update/
├── SKILL.md
├── step-00-init.md         (parse args, load feature meta, validate state)
├── step-01-collect.md      (read PRD + current journey + git diff for the feature)
├── step-02-update.md       (per impacted journey: AI generates diff/rewrite)
├── step-03-publish.md      (push AFFiNE updates)
└── step-04-finish.md       (telemetry + progress)
```

### step-02 mechanics

For each impacted journey:

```bash
MODE=$(jq -r '.documentation.auto_update_mode // "diff"' .snap/.config-resolved.json)

if [ "$MODE" = "diff" ]; then
  # AI prompt: read current journey doc, identify sections impacted by PRD,
  # patch only those sections, preserve rest verbatim
  patched=$(...)
elif [ "$MODE" = "rewrite" ]; then
  # AI prompt: regenerate full journey doc combining current state + PRD changes
  rewritten=$(...)
fi
```

### Acceptance

- Journey page(s) updated in AFFiNE
- Telemetry event `doc-update`, status `ok`
- progress.json entry
- PRD page **not touched**

## New `/snap:doc-import` skill

Bootstrap-import. Reads existing AFFiNE pages (workspace or root) → proposes
domain/journey split for snap → restructures. Targets projects with
upstream docs that don't match the snap hierarchy.

### Use cases

- Onboarding an existing project with free/scattered accumulated AFFiNE doc

### Flags

```
/snap:doc-import
  --source-page=<page-id-or-url>        # AFFiNE root to scan
                                         # (or entire workspace if absent)
  --strategy=move|copy|synthesize       # default: synthesize
  [--dry-run]                           # preview mapping, no AFFiNE write
  [--backup]                            # export source pages → .snap/.backup/
  [-a]                                  # autonomous (skip confirms)
  [--force]                             # bypass "_taxonomy.json non-empty" guard
```

### Strategies

| Strategy | Mechanics | When |
|----------|-----------|------|
| **synthesize** (default) | AI reads N source pages → consolidates into a single journey doc. Originals tagged `[snap-imported]`. | Existing doc messy/scattered. |
| **copy** | Duplicates content to new snap-path pages. Originals moved to `Archive/imported-{date}/`. | Preserve verbatim content. |
| **move** | Relocates source pages to snap-path (rename + reparent). Preserves AFFiNE history. | Doc already well structured, just wrong path. |

### Steps

```
skills/doc-import/
├── SKILL.md
├── step-00-init.md           (parse args, prereq /snap:init done, validate platform)
├── step-01-crawl.md          (MCP affine lists pages under source-page, builds index)
├── step-02-analyze.md        (AI: proposes domains + journeys + page→target mapping)
├── step-03-confirm.md        (AskUserQuestion review mapping, edit JSON via $EDITOR)
├── step-04-restructure.md    (execute strategy)
└── step-05-finish.md         (write _taxonomy.json + telemetry + progress)
```

### step-02 proposed JSON output

```json
{
  "proposed_structure": {
    "domains": {
      "auth": {
        "title": "Authentication",
        "source_pages": ["pid-1", "pid-3", "pid-7"],
        "journeys": {
          "login-flow": {
            "title": "Login Flow",
            "source_pages": ["pid-1", "pid-3"],
            "synthesized_excerpt": "..."
          },
          "signup-flow": {
            "title": "Signup Flow",
            "source_pages": ["pid-7"],
            "synthesized_excerpt": "..."
          }
        }
      }
    }
  },
  "unmapped_pages": [
    { "page_id": "pid-99", "title": "Random notes", "reason": "no clear domain" }
  ]
}
```

`unmapped_pages` = stay under source root, not migrated (user decides manually).

### Guardrails

- Explicit confirmation before step-04 (recap table of N affected pages)
- `--backup` strongly recommended (stderr warning if absent)
- Refuses run if `_taxonomy.json` is non-empty AND no `--force` (already imported once)
- Partial idempotent: re-run after fail skips already migrated pages (tracked via tag
  `[snap-imported]`)
- Telemetry event `doc-import` with status + number of affected pages

### Post-import output

- ✅ `Product Docs/` populated (domains + journeys)
- ✅ `_taxonomy.json` filled
- ❌ `Change Requests/` empty (PRDs come via future `/snap:define`)
- ❌ feature `manifest.json` absent (no story_id yet — will come with PRDs)

### User workflow

1. `/snap:init` (bootstrap config)
2. `/snap:doc-import --source-page=<root>` (this skill) → snap structure populated
3. `/snap:define --feature=NN-...` (first change post-import) → creates manifest.json
   - PRD + link to existing journey via `_taxonomy.json`

## Scripts changes

### `docs-adapter.sh` added actions

- `lookup-page --path=...` — find page by full path, returns `{page_id, url}` or exits 1 if absent
- `lookup-or-create-page --path=... --title=... [--parent-id=...]` — idempotent
- `update-page-content --page-id=... --content-file=...` — overwrite body
- `set-page-tags --page-id=... --tags=tag1,tag2` — replace tags list
- `create-page-tree --path=...` — recursive parent creation, returns leaf page_id

### `taxonomy-state.sh` (new)

```bash
taxonomy-state.sh add-domain --slug=auth --title="Authentication" --page-id=... --url=...
taxonomy-state.sh add-journey --domain=auth --slug=login-flow --title="Login Flow" --page-id=... --url=...
taxonomy-state.sh get-domain --slug=auth                        # JSON or exit 1
taxonomy-state.sh get-journey --domain=auth --slug=login-flow   # JSON or exit 1
taxonomy-state.sh list-domains                                  # NDJSON
taxonomy-state.sh list-journeys --domain=auth                   # NDJSON
taxonomy-state.sh validate                                      # schema check
```

### `manifest.schema.json`

Fields:

- `domains` (array), `impacted_journeys` (array), `prd` (object)

## Implementation order

1. **Schemas** — `config.schema.json` + `manifest.schema.json` + new `domains.schema.json`
2. **Shared scripts** — `taxonomy-state.sh` + new `docs-adapter.sh` actions
3. **Init skill** — `step-00-detect.md` ask paths (functional_root, prd_root)
4. **Doc-import skill** — full creation of `skills/doc-import/`
5. **Define skill** — `step-03-features.md` ask domains/journeys, `step-05-publish.md` refactor publish
6. **Doc-update skill** — full creation of `skills/doc-update/`
7. **QA hook** — `qa/step-finish.md` conditional doc-update trigger
8. **Tests** — extend `test-define-e2e.sh`, new `test-doc-import-e2e.sh`, `test-doc-update-e2e.sh`, `test-taxonomy-state.sh`, `test-docs-adapter.sh` (new actions)
9. **Docs** — update `docs/contributing/decisions.md`, `docs/contributing/scripts.md`, `docs/usage/skills/define.md`, new `docs/usage/skills/doc-import.md` + `docs/usage/skills/doc-update.md`
10. **CHANGELOG** — `[Unreleased]` section BREAKING CHANGE

## Settled decisions (cf. decisions.md to amend)

- PRD (archive) vs functional doc (living) distinction at the heart of the model
- Functional hierarchy: `domain → user journey`, configurable via `documentation.paths.*`
- PRD path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (date-based, flat, not by domain)
- Domains = multi tags on PRD (not in path)
- No change log on domain page (avoids bloat)
- No direct journey → PRD link (journey = own spec, PRD = external archive)
- Post-ship auto-update via `/snap:doc-update` skill, mode `diff` (default) or `rewrite`
- PRD frozen after creation (immutable, never re-touched)
- user_journey slug free, human page title
- `/snap:doc-import` skill for bootstrap from existing AFFiNE doc (3 strategies: synthesize default, copy, move)
