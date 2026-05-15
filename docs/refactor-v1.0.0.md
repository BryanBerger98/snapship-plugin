# Refactor v0.6.0 → v1.0.0 — `.snap/` workspace + remote-first architecture

> **Status**: planning. Not yet executed. Plan en cours de validation avec l'utilisateur.

## 1. Vue d'ensemble

Refactor majeur du workspace local du plugin snap. Migre `.claude/product/`
vers `.snap/` à la racine projet, simplifie la structure, et acte le principe
**remote = source de vérité, local = staging pré-push**.

Inclut un nouveau skill `/snap:upgrade` pour migrer automatiquement les
workspaces existants v0.x → v1.0.

## 2. Principe directeur

**Toutes les plateformes distantes configurées sont sources de vérité.**

- Docs (Notion / AFFiNE) → PRDs, galleries, page audit
- Tickets (GitHub / GitLab / Linear / Jira) → tickets
- Design files (Figma / Penpot / Frame0) → fichiers design

Le local sert uniquement à :
- Pré-générer / valider du contenu avant push remote
- Stocker des **références** (URL, IDs) vers les ressources distantes
- Cacher temporairement de l'état multi-step (drafts, queues)

Aucun fichier éphémère hors `.snap/` (pas de `$TMPDIR`). Tout reste dans le
workspace du dépôt, gitignoré.

## 3. Structure cible `.snap/`

```
.snap/
  # Catalogue versionné (commit)
  manifests/
    {slug}.manifest.json              ✅ commit — pointeurs + sync state
    _taxonomy.json                    ✅ commit — domains + journeys page IDs partagés
  
  # Machine state local (gitignore)
  progress.json                       ❌ in-flight skills, purge runtime, JSON
  telemetry.ndjson                    ❌ métriques locales, append-only
  
  # Staging pré-push (gitignore, trash post-ack)
  PRDs/{slug}.md
  designs/{slug}/{screen}.{svg,png}
  wireframes/{slug}/{screen}.{svg,png}
  tickets/{slug}.json                 # bloque si pas tracker platform configuré
  
  # Loop state (gitignore, vit pendant skill)
  queues/{slug}.develop.json
  
  # Workspace state (gitignore, éphémère)
  .define-state.json                  # multi-step /define, trash post-publish
  .doc-import/
    cache/{page_id}.md
    index.ndjson                      # status=ok|fail embed
  
  # Backups migration (gitignore, garde forever — user trash manuel)
  .bak-v{version}-{timestamp}/
```

**Principe** : tout reste dans `.snap/` (jamais `$TMPDIR`), gitignoré sauf
`manifests/`. Refs distantes vivent dans les manifests.

**Removed vs v0.6.0** :
- `.claude/product/` → `.snap/`
- `features/{id}/` → split par type (`PRDs/`, `manifests/`, `designs/`, etc.)
- `manifest.json` → `manifests/{slug}.manifest.json` (enrichi avec refs distantes)
- `prd-feature.md` → `PRDs/{slug}.md`
- `index.md` racine → dérivable de manifests, dropped
- `.config-resolved.json` → var bash intra-skill, stdout `load-config.sh`
- `.docs-cache.json` → refs distribuées dans chaque manifest
- `_taxonomy.json` → `manifests/_taxonomy.json`
- `progress.json` → `progress.json` (JSON machine state, purge runtime, gitignore)
- `design-gallery.md` → pipe direct stdout vers push MCP
- `.doc-import-{proposal,failures}.{json,ndjson}` → fold dans `.doc-import/`
- `.doc-update-cache/` → drop, re-pull always
- `daemon.sh` + mode `--loop=daemon` + `step-03c-loop-daemon.md` → dropped
- `features/{id}/progress.json` per-feature → dropped

**Bash rename** : `PRODUCT_DIR` → `SNAP_DIR` global.

## 4. Schéma manifest (v1.0.0)

```json
{
  "schema_version": "1.0.0",
  "feature_id": "01-auth",
  "feature_name": "Auth",
  "state": "shipped",
  "created_at": "2026-05-15T10:00:00Z",
  "lang": "fr",
  "green_field": true,
  "domains": ["auth"],
  "impacted_journeys": ["onboarding"],
  "refs": {
    "prd": {
      "platform": "notion",
      "url": "https://notion.so/...",
      "page_id": "abc-123",
      "synced_at": "2026-05-15T11:00:00Z",
      "sync_status": "synced"
    },
    "design_gallery":    { "platform":"notion","url":"...","page_id":"...","synced_at":"...","sync_status":"synced" },
    "wireframes_gallery":{ "platform":"notion","url":"...","page_id":"...","synced_at":"...","sync_status":"synced" },
    "tickets":           { "platform":"linear","url":"...","project_id":"...","synced_at":"..." },
    "design_file":       { "platform":"figma","url":"...","file_key":"..." }
  }
}
```

`sync_status` enum : `local-only` | `pending` | `synced` | `dirty` | `error`.

## 5. Schéma `_taxonomy.json` (v1.0.0)

```json
{
  "schema_version": "1.0.0",
  "workspace": {
    "platform": "notion",
    "workspace_id": "...",
    "root_page_id": "...",
    "activity_log_page_id": "..."
  },
  "domains": {
    "auth":     { "page_id": "...", "url": "...", "synced_at": "..." },
    "billing":  { "page_id": "...", "url": "...", "synced_at": "..." }
  },
  "journeys": {
    "onboarding": { "page_id": "...", "url": "...", "synced_at": "..." }
  }
}
```

## 6. `progress.json` — schéma + cycle de vie

```json
{
  "schema_version": "1.0.0",
  "in_flight": [
    {
      "skill": "define",
      "feature_id": "01-auth",
      "started_at": "2026-05-15T10:00:00Z",
      "steps": [
        { "num": "00", "name": "init",     "status": "ok",      "ts": "..." },
        { "num": "01", "name": "vision",   "status": "ok",      "ts": "..." },
        { "num": "02", "name": "personas", "status": "started", "ts": "..." }
      ]
    }
  ]
}
```

### Cycle de vie
| Événement | Action sur `progress.json` |
|---|---|
| Skill démarre | Append `{ skill, feature_id, started_at, steps:[] }` dans `in_flight[]` |
| Step démarre | Append `{ num, name, status:"started", ts }` aux `steps[]` |
| Step termine | Update dernier step `status` (ok\|fail\|skip\|retry) |
| Terminal step ok | **Trash** entrée du skill dans `in_flight[]` |
| Terminal step fail/abort | Garde entrée (resume possible) |
| `--resume` | Lit `in_flight[]`, trouve skill + feature, reprend au step `started` |

Steady state : `in_flight` = `[]` (tous skills terminés OK).

`progress.json` remplace l'ancien `progress.json` partout. Helper script `_shared/progress.sh` :
```
progress.sh start --skill=X --feature-id=Y
progress.sh step --skill=X --feature-id=Y --step-num=NN --step-name=NAME --status=STATUS [--note=TEXT]
progress.sh finish --skill=X --feature-id=Y --status=ok|fail
progress.sh resume --skill=X --feature-id=Y    # stdout: last in-flight step name
```

## 7. Versioning + `/snap:upgrade`

### Source de vérité version

- `snapship.config.json.version` — version plugin attendue par le projet
- `.snap/manifests/_taxonomy.json.schema_version` — version workspace state
- `.snap/manifests/{slug}.manifest.json.schema_version` — version par manifest
- `.claude-plugin/plugin.json.version` — version plugin installée

Skill detect mismatch au démarrage (`_shared/load-config.sh`) :
- Same → OK
- Different patch/minor → silent bump (compat backward)
- Different major → **BLOCK**, exige `/snap:upgrade`

### Framework migrations

```
skills/_shared/migrations/
  registry.json                       # ordered chain + breaking flags + decisions schema
  v0.6.0_to_v1.0.0.sh                 # cette refactor
  README.md                           # comment ajouter une migration
```

Chaque migration script :
- Lit env vars `SNAP_PROJECT_ROOT`, `SNAP_DECISIONS_JSON` (decisions user-validées)
- Idempotent (re-run safe)
- Exit 0 = success, 1 = fail (rollback depuis backup)

### Skill `/snap:upgrade`

```
skills/upgrade/
  SKILL.md
  step-00-detect.md      # detect current + target version, plan chain
  step-01-confirm.md     # show plan + AskUserQuestion decisions
  step-02-backup.md      # .snap.bak-{ts}/
  step-03-apply.md       # run migrations
  step-04-validate.md    # schemas + paths
  step-05-finish.md      # bump versions, suggest /snap:fetch
```

Pseudo-code orchestration :

```
detect_versions()
chain = resolve_migration_chain(current → target)
if chain.has_breaking:
  decisions = ask_user_questions(chain.decisions_schema)
backup(.snap → .snap.bak-{version}-{ts}/)
for migration in chain:
  apply(migration, decisions) || rollback() && exit 1
validate_workspace()
bump_versions()
suggest("/snap:fetch  # re-sync depuis remote")
```

### Migration v0.6.0 → v1.0.0 — décisions user

| Décision | Question (`AskUserQuestion`) | Default |
|---|---|---|
| Ancien `.claude/product/` | Garder en `.bak-v0.6.0-{ts}/`, trash, ou laisser intact ? | Garder backup |
| Re-publier PRDs vers remote ? | Forcer refresh ou se fier aux refs manifests ? | Skip |
| Créer page "Snap Activity Log" remote ? | Initialiser audit page distant ? | Oui |
| Tickets sans tracker config | "Pas de tracker config. Configure maintenant, sinon `/ticket` sera bloqué." | Configure |
| Mode daemon utilisateurs | "Mode `--loop=daemon` supprimé. OK basculer en `--loop=session` ?" | Oui |

## 8. Skill `/snap:fetch` (nouveau)

Re-sync local depuis remote. Pour cas : doc modifiée/supprimée à distance,
ou besoin de re-éditer un PRD synced.

```
skills/fetch/
  SKILL.md
  step-00-resolve.md     # parse args: --feature=slug, --kind=prd|design|wireframe|all
  step-01-fetch.md       # pull depuis remote via MCP adapter
  step-02-write.md       # write staging files dans .snap/PRDs/, designs/, etc.
  step-03-update.md      # update manifest.refs.<kind>.synced_at + sync_status="synced"
```

Cas d'usage :
- `/snap:fetch --feature=01-auth --kind=prd` → re-pull PRD pour edit
- `/snap:fetch --feature=01-auth --kind=all` → re-pull tout
- `/snap:fetch --all` → re-pull all features + taxonomy

Détection désync : **opt-in** via `/snap:fetch --check`. Compare
`manifests/*.synced_at` avec `last_edited_time` remote. Si remote plus récent →
marque `sync_status="dirty"` + suggère fetch. Pas auto au boot skill (coût
réseau).

## 9. Sync pattern unifié

Logique partagée dans `_shared/sync-push.sh` :

```bash
# push_to_remote --feature-id=X --kind=prd|design|...
1. validate local staging file (schemas)
2. call docs-adapter/tickets-adapter push
3. if ack ok:
   a. update manifest.refs.<kind> { url, page_id, synced_at, sync_status="synced" }
   b. trash local staging file
4. else:
   a. mark manifest.refs.<kind>.sync_status="dirty"
   b. surface error code + stderr to user
```

## 10. Liste exhaustive modifications

### Renames de chemins (sed bulk)
- `.claude/product/` → `.snap/` (92 fichiers)
- `${PRODUCT_DIR}` → `${SNAP_DIR}` (scripts shared)
- `manifest.json` → `manifest.json` (au cas par cas, car déplacement de dir aussi)
- `features/{id}/prd-feature.md` → `PRDs/{slug}.md`
- `features/{id}/tickets.json` → `tickets/{slug}.json`
- `features/{id}/design/...` → `designs/{slug}/...`
- `features/{id}/wireframes/...` → `wireframes/{slug}/...`
- `features/{id}/.develop-queue.json` → `queues/{slug}.develop.json`

### Fichiers à modifier (skills)

**init** :
- `step-01-write.md` — nouveau scaffold `.snap/manifests/`, `_taxonomy.json`, drop `index.md`, drop `progress.json` local
- `SKILL.md` — outputs section

**define** :
- `step-04-render.md` — écrit `PRDs/{slug}.md` + `manifests/{slug}.manifest.json` (avec `refs.prd.sync_status="local-only"`)
- `step-05-publish.md` — push PRD vers Notion/AFFiNE, update manifest refs, trash local PRD, créer/update page activity log remote
- `step-00-init.md`, `step-01-vision.md`, `step-02-personas.md`, `step-03-features.md` — adapter paths `.define-state.json`

**ticket** :
- Adapter `tickets/{slug}.json` au lieu de `features/{id}/tickets.json`
- Bloquer si `tickets_platform=none`

**design** + **wireframe** :
- Drafts dans `.snap/` (pas `$TMPDIR`) mais marqués éphémères
- Assets staging → `designs/{slug}/`, `wireframes/{slug}/`
- Post-upload : trash assets, update manifest refs
- `design-gallery.md` → pipe stdout direct

**develop** :
- Supprimer `step-03c-loop-daemon.md`
- Adapter `queues/{slug}.develop.json`
- `step-05-finish.md` — drop refresh `index.md`

**doc-import** + **doc-update** :
- Fold cache dans `.doc-import/`
- Drop `.doc-update-cache/`

**qa** :
- Adapter paths

### Shared scripts à modifier
- `setup-snap-dir.sh` → renomme `setup-snap-dir.sh`, nouveau scaffold
- `load-config.sh` — stdout au lieu de fichier `.config-resolved.json`
- `progress.sh` — push vers remote au lieu de write local
- `define-state.sh`, `taxonomy-state.sh`, `telemetry.sh`, `docs-adapter.sh`,
  `tickets-adapter.sh`, `figma-helper.sh`, `frame0-helper.sh`, `penpot-helper.sh`
  — adapter paths
- **Nouveau** `sync-push.sh` — pattern unifié push + ack + trash
- **Nouveau** `sync-fetch.sh` — pattern unifié pull + write staging

### Schémas
- `manifest.schema.json` → `manifest.schema.json` (enrichi avec `refs`)
- `domains.schema.json` → `taxonomy.schema.json` (workspace + domains + journeys)
- `config.schema.json` — ajoute champ `version` requis

### Nouveau code
- Skill `/snap:upgrade` (8 fichiers)
- Skill `/snap:fetch` (5 fichiers)
- `_shared/migrations/v0.6.0_to_v1.0.0.sh`
- `_shared/migrations/registry.json`
- `_shared/migrations/README.md`

### Docs à mettre à jour
- `CHANGELOG.md` — v1.0.0 entry détaillée (breaking changes)
- `README.md` — exemples chemins, install instructions
- `docs/structure.md` — refait à neuf
- `docs/modes.md` — drop daemon mode
- `docs/scripts.md` — nouveaux scripts
- `docs/templates.md` — drop daemon template
- `docs/decisions.md` — ADR "Remote-first architecture"
- `docs/configuration.md` — versioning section
- `agents/*.md` — chemins

### Gitignore
```
# v0.x legacy
.claude/product/

# v1.0
.snap/*
!.snap/manifests/
!.snap/manifests/**

# Backups migration
.snap.bak-*/
```

## 11. Plan exec — 1 gros commit

Ordre intra-commit :
1. Écrire `docs/refactor-v1.0.0.md` (ce fichier)
2. Bump `plugin.json` version → `1.0.0`
3. Update `config.schema.json` (add `version` field)
4. Create migration framework (`_shared/migrations/`)
5. Create `/snap:upgrade` skill
6. Create `/snap:fetch` skill
7. Create new schemas (`manifest.schema.json`, `taxonomy.schema.json`)
8. Create `sync-push.sh`, `sync-fetch.sh`
9. Refactor `setup-snap-dir.sh` → `setup-snap-dir.sh` (new scaffold)
10. Refactor `load-config.sh` (stdout)
11. Refactor `progress.sh` (remote push)
12. Sed bulk rename `.claude/product/` → `.snap/`, `PRODUCT_DIR` → `SNAP_DIR`
13. Sed paths per-feature → split par type
14. Restructure skills affectés (init, define, ticket, design, wireframe, develop, doc-import, doc-update, qa)
15. Drop daemon (`step-03c-loop-daemon.md`, template, modes refs)
16. Update gitignore
17. Update docs (README, CHANGELOG, structure, modes, scripts, templates, decisions, config, agents)
18. Run tests bats — adapter ceux qui cassent
19. Manual smoke test : `/snap:init` puis `/snap:define` skeleton

## 12. Validation post-refactor

- [ ] `bash skills/_shared/setup-snap-dir.sh` crée structure attendue
- [ ] `bash skills/_shared/load-config.sh` retourne JSON valide stdout
- [ ] Tous tests bats passent (ou marquées migration TODO)
- [ ] `manifest.schema.json` valide un manifest exemple
- [ ] `taxonomy.schema.json` valide un taxonomy exemple
- [ ] `/snap:upgrade` détecte un workspace v0.6.0 et plan migration correcte
- [ ] `/snap:fetch --feature=X --kind=prd` re-pull et update manifest
- [ ] CHANGELOG v1.0.0 entry complète
- [ ] Pas de référence résiduelle à `.claude/product/`, `manifest.json`, `daemon`,
      `PRODUCT_DIR` (grep verify)

## 13. Décisions finales (toutes tranchées)

| # | Décision | Choix |
|---|---|---|
| 1 | Versioning : `schema_version` per manifest | ✅ Oui, dans chaque manifest + `_taxonomy.json` + `config.json` |
| 2 | Backup migration TTL | ✅ Garde forever, user trash manuel |
| 3 | Migration semi-auto, breaking = `AskUserQuestion` | ✅ OK |
| 4 | MAJOR mismatch = BLOCK, MINOR/PATCH = silent | ✅ OK |
| 5 | `/snap:upgrade --dry-run` inclus | ✅ Oui |
| 6 | `progress.json` historique migration | ✅ Fresh start, garde uniquement steps unfinished (in-flight) pour resume |
| 7 | Désync detection | ✅ Opt-in via `/snap:fetch --check` |
| 8 | Activity log remote | ❌ Dropped |
| 9 | `progress` format | ✅ JSON (`progress.json`), purge runtime |
| 10 | `$TMPDIR` pour éphémères | ❌ Tout reste dans `.snap/` |
| 11 | Commit | ✅ 1 gros commit |
| 12 | `/snap:fetch` création | ✅ Maintenant |
| 13 | Mode `--loop=daemon` | ❌ Dropped (session only) |
| 14 | `tickets` sans tracker | ✅ BLOQUE (exige plateforme config) |
| 15 | Telemetry | ✅ Garde (gitignore) |
