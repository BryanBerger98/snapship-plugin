# Documentation Architecture v0.2

Refonte du modèle documentation produit. Sépare PRD (archive immuable d'une
évolution) de la doc fonctionnelle vivante (spec courante d'un user journey).

> **État:** spec brouillon. Implémentation v0.2 du plugin (post-v0.1.0
> dogfooding). Breaking change vs v0.1.0.

## Concepts

| Type | Cycle | Contenu | Versioning |
|------|-------|---------|------------|
| **PRD / Change request** | Court terme — 1 par évolution | Ce qui VA changer + pourquoi (deltas, AC, scope) | Archivé immuable post-ship |
| **Doc fonctionnelle (journey)** | Long terme — vivante | Ce que la feature FAIT aujourd'hui (flows, règles, contracts) | Updated chaque ship via `/snap:doc-update` |
| **Domain page** | Long terme — vivante | Overview d'un domaine produit, liens vers journeys | Update uniquement si nouveaux journeys ajoutés |

Pas de log des modifications sur domain page (éviterait pages énormes au fil des
cycles). Historique = via les pages PRD elles-mêmes (filtrables AFFiNE par tag +
date).

## Hiérarchie AFFiNE

```
{functional_root}/             ex: "Product Docs"
└── {domain}/                   ex: "auth"
    ├── (domain page = overview, links to journeys)
    ├── Login Flow              ← user journey page
    ├── Signup Flow
    └── Password Reset

{prd_root}/                     ex: "Change Requests"
└── {YYYY}/
    └── {MM-YYYY}/
        └── {NN-feature_slug}   ← PRD page (tags: domains impactés)
```

Exemple chemin PRD: `Change Requests/2026/05-2026/01-bouton-login-simple`.

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

| Field | Default | Rôle |
|-------|---------|------|
| `paths.functional_root` | `"Product Docs"` | Page racine doc fonctionnelle vivante |
| `paths.prd_root` | `"Change Requests"` | Page racine archive PRD |
| `auto_update_mode` | `"diff"` | Mode update journey post-ship: `diff` (patch sections impactées) ou `rewrite` (regenerate full) |
| `auto_update_on_qa_success` | `true` | Trigger auto `/snap:doc-update` quand `/snap:qa` valide |

## Storage local

### `.snap/manifests/_taxonomy.json` (nouveau)

Cache de mapping domains + journeys ↔ AFFiNE page IDs. Évite re-lookup à chaque
skill run, suggère valeurs existantes au prochain `/snap:define`.

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

### `manifest.json` feature (révisé)

```json
{
  "feature_id": "01-bouton-login-simple",
  "feature_name": "Bouton login simple",
  "state": "defined | in-progress | qa-validated",
  "domains": ["auth", "dashboard"],
  "impacted_journeys": [
    { "domain": "auth", "journey_slug": "login-flow" },
    { "domain": "dashboard", "journey_slug": "overview" }
  ],
  "prd": {
    "page_id": "...",
    "url": "...",
    "path": "Change Requests/2026/05-2026/01-bouton-login-simple"
  },
  "created_at": "2026-05-09T16:34:22Z",
  "updated_at": "2026-05-15T10:00:00Z"
}
```

Champ `affine_page_id` (v0.1) supprimé. Replacé par `prd.page_id`.

## Slugs vs titres

- **Page AFFiNE titre** = humain ("Login Flow", "Signup Flow")
- **Slug interne** = kebab-case (`login-flow`) pour cache + referencement

Slug user_journey libre (pas d'enum config). User saisit titre → slug auto-généré
(slugify), ou user override slug explicite.

## Workflow `/snap:define` révisé

### step-03-features (modifié)

Pour chaque feature, après collecte AC + scope, demander:

1. **Domains impactés** (multi-select + free input):
   - Suggest depuis `_taxonomy.json` (déjà connus)
   - Allow ajouter nouveau domain (saisie title + slug auto)

2. **Journeys impactés par domain**:
   - Pour chaque domain choisi: select journeys existants OU créer nouveau
   - Si nouveau: ask title humain → slug auto

Persiste dans state file + plus tard manifest.json.

### step-05-publish (refactor majeur)

Pour chaque feature:

1. **Compute PRD path**:

   ```bash
   YEAR=$(date +%Y)
   MONTH_YEAR=$(date +%m-%Y)
   PRD_PATH="${PRD_ROOT}/${YEAR}/${MONTH_YEAR}/${FEATURE_ID}"
   ```

2. **Create PRD page** (toujours nouveau, pas d'idempotence — feature unique par
   feature_id):
   - Title: feature_name
   - Tags: liste domains impactés
   - Body: rendered `prd-feature.md`
   - Parent: lookup-or-create `{prd_root}/{YYYY}/{MM-YYYY}` (récursif si absent)

3. **Lookup-or-create domain pages** (idempotent):
   - Pour chaque domain dans `feature.domains`:
     - Lookup `{functional_root}/{domain}` dans `_taxonomy.json`
     - Si miss: create page → save `domain_page_id` dans `_taxonomy.json`

4. **Lookup-or-create journey pages** (idempotent):
   - Pour chaque `(domain, journey_slug)` dans `feature.impacted_journeys`:
     - Lookup dans `_taxonomy.json[domain].journeys[journey_slug]`
     - Si miss: create page sous domain page → save dans `_taxonomy.json`
     - Si nouveau: page initialisée vide (sera populée par premier
       `/snap:doc-update` post-ship)

5. **Save IDs**:
   - `feature.manifest.json`: `prd.page_id`, `prd.url`, `prd.path`
   - `_taxonomy.json`: nouveaux domain/journey entries

6. **PAS de modification**:
   - PAS de log entry sur domain page
   - PAS de lien direct journey → PRD
   - PRD page ne sera plus jamais touchée après création

## Nouveau skill `/snap:doc-update`

### Trigger

| Source | Condition |
|--------|-----------|
| Auto post-`/snap:qa` | `documentation.auto_update_on_qa_success: true` AND state passe `qa-validated` |
| Manuel | `/snap:doc-update --feature=NN-slug` |

### Steps

```
skills/doc-update/
├── SKILL.md
├── step-00-init.md         (parse args, load feature meta, validate state)
├── step-01-collect.md      (lire PRD + journey current + diff git de la feature)
├── step-02-update.md       (par journey impacté: AI generate diff/rewrite)
├── step-03-publish.md      (push updates AFFiNE)
└── step-04-finish.md       (telemetry + progress)
```

### Mécanique step-02

Pour chaque journey impacté:

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

- Journey page(s) AFFiNE updated
- Telemetry event `doc-update`, status `ok`
- progress.json entry
- PRD page **non touchée**

## Nouveau skill `/snap:doc-import`

Bootstrap-import. Lit pages AFFiNE existantes (workspace ou racine) → propose
découpage domains/journeys snap → restructure. Cible projets avec doc legacy
amont qui ne respecte pas la hiérarchie snap.

### Cas d'usage

- Onboarding projet existant avec doc AFFiNE accumulée libre/scattered
- Pas pour migration snap v0.1 → v0.2 (drop pour pilote, pas de migration script)

### Flags

```
/snap:doc-import
  --source-page=<page-id-or-url>        # racine AFFiNE à scanner
                                         # (ou workspace entier si absent)
  --strategy=move|copy|synthesize       # default: synthesize
  [--dry-run]                           # preview mapping, no AFFiNE write
  [--backup]                            # export source pages → .snap/.backup/
  [-a]                                  # autonome (skip confirms)
  [--force]                             # bypass garde "_taxonomy.json non-vide"
```

### Stratégies

| Strategy | Mécanique | Quand |
|----------|-----------|-------|
| **synthesize** (default) | AI lit N pages source → consolide en journey doc unique. Originaux taggés `[snap-imported]`. | Doc legacy messy/scattered. |
| **copy** | Duplique content vers nouvelles pages snap-path. Originaux move vers `Archive/imported-{date}/`. | Conserver contenu verbatim. |
| **move** | Relocate pages source vers snap-path (rename + reparent). Préserve historique AFFiNE. | Doc déjà bien structurée, juste mauvais path. |

### Steps

```
skills/doc-import/
├── SKILL.md
├── step-00-init.md           (parse args, prereq /snap:init done, validate platform)
├── step-01-crawl.md          (MCP affine list pages sous source-page, build index)
├── step-02-analyze.md        (AI: propose domains + journeys + mapping page→target)
├── step-03-confirm.md        (AskUserQuestion review mapping, edit JSON via $EDITOR)
├── step-04-restructure.md    (execute strategy)
└── step-05-finish.md         (write _taxonomy.json + telemetry + progress)
```

### step-02 output JSON proposé

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

`unmapped_pages` = restent sous source root, pas migrées (user décide manuel).

### Garde-fous

- Confirmation explicite avant step-04 (table récap N pages affectées)
- `--backup` recommandé fortement (warning stderr si absent)
- Refuse run si `_taxonomy.json` non-vide ET pas `--force` (déjà importé une fois)
- Idempotent partial: re-run après fail skip pages déjà migrées (track via tag
  `[snap-imported]`)
- Telemetry event `doc-import` avec status + nombre pages affectées

### Output post-import

- ✅ `Product Docs/` populé (domains + journeys)
- ✅ `_taxonomy.json` rempli
- ❌ `Change Requests/` empty (PRDs viennent via futurs `/snap:define`)
- ❌ `manifest.json` features absent (pas de feature_id encore — viendra avec PRDs)

### Workflow user

1. `/snap:init` (bootstrap config)
2. `/snap:doc-import --source-page=<root>` (cette skill) → snap structure populée
3. `/snap:define --feature=NN-...` (premier change post-import) → crée manifest.json
   - PRD + lie au journey existant via `_taxonomy.json`

## Scripts changes

### `docs-adapter.sh` actions ajoutées

- `lookup-page --path=...` — find page by full path, return `{page_id, url}` ou exit 1 si absent
- `lookup-or-create-page --path=... --title=... [--parent-id=...]` — idempotent
- `update-page-content --page-id=... --content-file=...` — overwrite body
- `set-page-tags --page-id=... --tags=tag1,tag2` — replace tags list
- `create-page-tree --path=...` — recursive parent creation, return leaf page_id

### `taxonomy-state.sh` (nouveau)

```bash
taxonomy-state.sh add-domain --slug=auth --title="Authentication" --page-id=... --url=...
taxonomy-state.sh add-journey --domain=auth --slug=login-flow --title="Login Flow" --page-id=... --url=...
taxonomy-state.sh get-domain --slug=auth                        # JSON ou exit 1
taxonomy-state.sh get-journey --domain=auth --slug=login-flow   # JSON ou exit 1
taxonomy-state.sh list-domains                                  # NDJSON
taxonomy-state.sh list-journeys --domain=auth                   # NDJSON
taxonomy-state.sh validate                                      # schema check
```

### `manifest.schema.json` modifié

Diff vs v0.1:

- DROP: `affine_page_id`, `affine_url`, `notion_page_id`, `notion_url`
- ADD: `domains` (array), `impacted_journeys` (array), `prd` (object)

## Migration v0.1 → v0.2

Pas de script migration. v0.1.0 = pilote dogfood seulement (1 user, 1 projet
test). v0.2 = wipe `.snap/manifests/` + redéfinir features avec
nouveau schéma.

Pour les vrais users (post-publication marketplace), v0.1 sera la version de
publication initiale ET v0.2 — pas de v0.1 publique. Donc no-op migration.

## Implementation order

1. **Schemas** — `config.schema.json` + `manifest.schema.json` + nouveau `domains.schema.json`
2. **Scripts shared** — `taxonomy-state.sh` + nouvelles actions `docs-adapter.sh`
3. **Init skill** — `step-00-detect.md` ask paths (functional_root, prd_root)
4. **Doc-import skill** — création complète `skills/doc-import/` (avant define refactor: permet bootstrap projet avec doc legacy)
5. **Define skill** — `step-03-features.md` ask domains/journeys, `step-05-publish.md` refactor publish
6. **Doc-update skill** — création complète `skills/doc-update/`
7. **QA hook** — `qa/step-finish.md` trigger doc-update conditionnel
8. **Tests** — extend `test-define-e2e.sh`, nouveaux `test-doc-import-e2e.sh`, `test-doc-update-e2e.sh`, `test-taxonomy-state.sh`, `test-docs-adapter.sh` (nouvelles actions)
9. **Docs** — update `docs/decisions.md`, `docs/scripts.md`, `docs/skills/define.md`, nouveaux `docs/skills/doc-import.md` + `docs/skills/doc-update.md`
10. **CHANGELOG** — section `[Unreleased]` BREAKING CHANGE

## Décisions actées (cf. décisions.md à amender)

- Distinction PRD (archive) vs doc fonctionnelle (vivante) au cœur du modèle
- Hiérarchie functional: `domain → user journey`, configurable via `documentation.paths.*`
- PRD path: `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (date-based, plat, pas par domaine)
- Domains = tags multi sur PRD (pas dans path)
- Pas de log modifications sur domain page (évite bloat)
- Pas de lien direct journey → PRD (journey = spec propre, PRD = archive externe)
- Auto-update post-ship via `/snap:doc-update` skill, mode `diff` (default) ou `rewrite`
- PRD figé après création (immuable, jamais re-touché)
- Slug user_journey libre, page title humain
- Skill `/snap:doc-import` pour bootstrap depuis doc legacy AFFiNE existante (3 stratégies: synthesize default, copy, move)
