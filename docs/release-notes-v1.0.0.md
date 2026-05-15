# snapship-plugin v1.0.0 — Remote-first workspace

Première release majeure. Refonte breaking orientée **plateformes distantes
= sources de vérité**. Le workspace local sert uniquement à pré-générer,
valider, stager avant push. Rien n'est dupliqué localement par défaut, sauf
`manifests/` et `tickets/` (références indispensables pour reprendre offline).

## Highlights

- **Layout `.snap/` réorganisé** — split par type (`manifests/`, `tickets/`,
  `PRDs/`, `designs/`, `wireframes/`, `queues/`, `progress.json`).
  Fin du `features/{slug}/` monolithique.
- **Helpers `_shared/` refactorés** — `progress.sh` unifié, nouveaux
  `sync-push.sh` / `sync-fetch.sh` (write-through outbox + replay refs).
- **State machine manifest** — `defined → ticketed → wireframed → designed
  → developed → qa-validated → shipped`.
- **`/snap:upgrade`** (nouveau) — migration framework idempotente,
  backup auto `.snap.bak-v0-{ts}/`.
- **`/snap:fetch`** (nouveau) — re-sync caches locaux depuis les
  plateformes (replay des refs du manifest).
- **Templates repo-native** — `/snap:ticket` et `/snap:develop` détectent
  et remplissent `.github/ISSUE_TEMPLATE/*.md`, `.gitlab/issue_templates/*.md`,
  `.github/PULL_REQUEST_TEMPLATE.md` au lieu de leur bundled fallback.
- **`/snap:design`** — réduit à la maquette hi-fi pure. Modes `ds-extract`
  / `ds-init` / `ds-update` retirés. CLI `bridge-ds` retiré.
- **`/snap:develop`** — drop du mode `daemon`. Boucle session-only.
- **Secrets** — `.env.snapship` racine projet pour les tokens
  (Figma notamment), helper `load-env.sh`.
- **Documentation utilisateur** — nouvelles pages `install.md`,
  `getting-started.md`, `troubleshooting.md`, `migration-v1.md` ;
  `config.md` renommé `configuration.md`.

## Breaking changes

| v0.6                                          | v1.0                                                |
| --------------------------------------------- | --------------------------------------------------- |
| `.snap/features/{slug}/meta.json`             | `.snap/manifests/{feature_id}.manifest.json`        |
| `.snap/features/{slug}/tickets.json`          | `.snap/tickets/{feature_id}.json`                   |
| `.snap/features/{slug}/wireframes/`           | `.snap/wireframes/{feature_id}/`                    |
| `.snap/features/{slug}/design/`               | `.snap/designs/{feature_id}/`                       |
| `.snap/features/{slug}/prd-feature.md`        | `.snap/PRDs/{feature_id}.md`                        |
| `.snap/features/{slug}/progress.md`           | `.snap/progress.json` (centralisé, gitignored)      |
| `.snap/domains.json`                          | `.snap/manifests/_taxonomy.json`                    |
| `.snap/index.md`                              | _supprimé_                                          |
| `.claude/product/` (legacy)                   | `.snap/`                                            |
| `update-progress.sh` + `resume-state.sh`      | `progress.sh` (sous-commandes)                      |
| `setup-product-dir.sh`                        | `setup-snap-dir.sh`                                 |
| `domains-state.sh`                            | `taxonomy-state.sh`                                 |
| `update-index.sh`                             | _supprimé_                                          |
| `develop.loop.daemon.*`                       | _retiré_ (schema rejette)                           |
| `design.extract.*`                            | _retiré_                                            |

## Migration

```text
/snap:upgrade --dry-run        # preview
/snap:upgrade                  # backup auto puis applique
/snap:fetch --all              # re-sync depuis remote
```

Détails complets : [docs/migration-v1.md](https://github.com/BryanBerger98/snapship-plugin/blob/main/docs/migration-v1.md).

## Tests

`1269 / 1269` tests bats passent sur 37 fichiers. CI shellcheck verte.

## Install

```bash
# Manuel global (marketplace bryanberger arrive juste après cette release)
git clone https://github.com/BryanBerger98/snapship-plugin ~/.claude/plugins/snap
```

Voir [docs/install.md](https://github.com/BryanBerger98/snapship-plugin/blob/main/docs/install.md).

---

**Full changelog** : [CHANGELOG.md](https://github.com/BryanBerger98/snapship-plugin/blob/main/CHANGELOG.md)
