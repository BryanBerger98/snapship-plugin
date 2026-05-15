# Migration v0.6 → v1.0

Snap v1.0.0 est un **refactor breaking** orienté « plateformes distantes =
sources de vérité ». Le local sert uniquement à pré-générer, valider, stager
avant push. Plus rien n'est dupliqué localement par défaut (sauf
`manifests/` et `tickets/`, références indispensables).

> **TL;DR** : lance `/snap:upgrade` dans chaque projet qui utilisait snap
> v0.6.x. Le skill détecte la version, backup `.snap/` (ou `.claude/product/`)
> vers `.snap.bak-v0-{timestamp}/`, applique les migrations, valide.

## Procédure recommandée

```text
/snap:upgrade --dry-run       # 1. preview du plan
/snap:upgrade                 # 2. applique (backup auto)
/snap:fetch --all             # 3. re-sync depuis remote pour absorber le drift
```

Failure pendant `step-03-apply` → rollback automatique depuis le backup.
Failure `step-04-validate` → workspace migré mais schémas à corriger
manuellement (pas de rollback à ce stade).

## Breaking changes — chemins

| v0.6                                                 | v1.0                                                |
| ---------------------------------------------------- | --------------------------------------------------- |
| `.snap/features/{slug}/meta.json`                    | `.snap/manifests/{feature_id}.manifest.json`        |
| `.snap/features/{slug}/tickets.json`                 | `.snap/tickets/{feature_id}.json`                   |
| `.snap/features/{slug}/wireframes/`                  | `.snap/wireframes/{feature_id}/`                    |
| `.snap/features/{slug}/design/`                      | `.snap/designs/{feature_id}/`                       |
| `.snap/features/{slug}/prd-feature.md`               | `.snap/PRDs/{feature_id}.md`                        |
| `.snap/features/{slug}/progress.md`                  | `.snap/progress.json` (centralisé, gitignored)      |
| `.snap/domains.json`                                 | `.snap/manifests/_taxonomy.json`                    |
| `.snap/index.md`                                     | _supprimé_ — état lu depuis `manifests/` + `_taxonomy.json` |
| `.claude/product/` (legacy)                          | `.snap/`                                            |
| `artysan.config.json`                                | `snapship.config.json`                              |

## Breaking changes — helpers `_shared/`

| v0.6                                              | v1.0                                              |
| ------------------------------------------------- | ------------------------------------------------- |
| `update-progress.sh` + `resume-state.sh`          | `progress.sh` (sous-commandes `start`/`step`/`finish`/`resume`) |
| `setup-product-dir.sh`                            | `setup-snap-dir.sh`                               |
| `domains-state.sh`                                | `taxonomy-state.sh`                               |
| `telemetry.sh emit` / `append`                    | `telemetry.sh log`                                |
| `load-config.sh` (cache `.config-resolved.json`)  | `load-config.sh` retourne sur stdout, pas de cache |
| `update-index.sh`                                 | _supprimé_ — manifests + taxonomy remplacent      |
| —                                                 | `sync-push.sh` (nouveau, write-through outbox)    |
| —                                                 | `sync-fetch.sh` (nouveau, replay refs)            |

## Breaking changes — skills

- **`/snap:develop`** : suppression du mode `daemon`. Boucle session-only.
  `develop.loop.daemon.*` retiré du schéma config.
- **`/snap:design`** : retiré modes `ds-extract` / `ds-init` / `ds-update`
  (déjà retirés en v0.6.x sous `refactor/design-mockup-only`). Le design
  system est géré hors plugin.
- **`/snap:upgrade`** (nouveau) : migration framework, idempotent.
- **`/snap:fetch`** (nouveau) : re-sync caches locaux depuis les
  plateformes (replay `refs` du manifest).

## Breaking changes — config (`snapship.config.json`)

| Clé v0.6                       | v1.0                                                  |
| ------------------------------ | ----------------------------------------------------- |
| `develop.loop.daemon`          | retirée — `additionalProperties:false` rejette       |
| `design.extract.*`             | retirée                                               |
| `design.figma.bridge_kb_path`  | retirée                                               |
| `design.figma.bridge_transport`| retirée                                               |
| —                              | `templates.use_repo_native` (bool, défaut `true`)     |
| —                              | `version` bumpée `0.6.x` → `1.0`                      |

Schemas `additionalProperties:false` ⇒ une clé orpheline = erreur de
validation. `/snap:upgrade` nettoie automatiquement.

## State machine — manifest

v1.0 introduit un état machine explicite sur chaque manifest
(`.snap/manifests/{feature_id}.manifest.json`) :

```
defined → ticketed → wireframed → designed → developed → qa-validated → shipped
```

Chaque skill terminal écrit la transition. `/snap:fetch` peut détecter un
drift entre l'état local et l'état remote (PR mergée hors snap, ticket fermé
manuellement) — il propose alors une réconciliation.

## `.gitignore`

v1.0 whiteliste `manifests/` et `tickets/`, ignore tout le reste :

```gitignore
.env.snapship
.env.snapship.*
.snap/*
!.snap/manifests/
!.snap/tickets/
.snap.bak-*
.config-resolved.json
.claude/product/
```

→ rien à régénérer côté équipe : `tickets/` + `manifests/` suffisent pour
qu'un nouveau membre puisse `/snap:fetch --all` et reconstruire le contexte.

## Vérification post-upgrade

```bash
jq '.version' snapship.config.json                # → "1.0"
jq '.schema_version' .snap/manifests/_taxonomy.json  # → "1.0"
ls .snap/manifests/                               # *.manifest.json + _taxonomy.json
ls .snap/tickets/                                 # *.json
test -f .snap/progress.json && echo OK            # central, plus de per-feature
test ! -d .claude/product/ && echo OK             # legacy purgé
```

Si une étape revient `KO`, lance `/snap:upgrade` à nouveau (idempotent) ou
restaure depuis `.snap.bak-v0-{timestamp}/`.

## Plus de détails

- [CHANGELOG.md](../CHANGELOG.md) — entrée v1.0.0 (toutes les ruptures)
- [structure.md](../contributing/structure.md) — nouvelle arbo `.snap/`
- [scripts.md](../contributing/scripts.md) — contrats helpers refactorés
