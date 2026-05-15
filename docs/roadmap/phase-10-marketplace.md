# Phase 10 — Marketplace `bryanberger`

**Objectif:** héberger snap (et futurs plugins) dans une marketplace personnelle GitHub découvrable via `/plugin marketplace add BryanBerger98/claude-plugins` (repo réel) puis `/plugin install snap@bryanberger` (alias marketplace `name`).

> Claude Code n'a pas de marketplace centrale Anthropic — chaque créateur publie via un repo GitHub contenant `.claude-plugin/marketplace.json`. Nom `bryanberger` libre (liste réservée complète: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `knowledge-work-plugins`, `life-sciences`).
>
> Source types acceptés: relative path (string), `github` (`{source:"github", repo, ref|sha}`), `url` (git URL), `git-subdir` (sous-dossier d'un repo git), `npm`. On utilise `github` avec `ref` = tag release.

## 10.1 Préparation plugin

- [x] Tag release `v1.0.0` sur repo plugin (`git tag -a v1.0.0 -m "..." && git push --tags`)
- [x] GitHub Release notes (extrait CHANGELOG.md) — [release v1.0.0](https://github.com/BryanBerger98/snapship-plugin/releases/tag/v1.0.0)
- [x] Setup issue templates (`bug.yml`, `feature.yml`, `question.yml`, `config.yml`) dans `.github/ISSUE_TEMPLATE/`

## 10.2 Création marketplace repo

- [x] Créer repo public `BryanBerger98/claude-plugins` (license MIT, README quickstart) — [github.com/BryanBerger98/claude-plugins](https://github.com/BryanBerger98/claude-plugins). Owner réel = `BryanBerger98` (compte GitHub authentifié) ; identifier marketplace = `bryanberger` (utilisé dans `/plugin install snap@bryanberger`).
- [x] Arbo:

  ```
  claude-plugins/
  └── .claude-plugin/
      └── marketplace.json
  ```

- [ ] `.claude-plugin/marketplace.json`:

  ```json
  {
    "name": "bryanberger",
    "owner": { "name": "Bryan Berger", "email": "contact@bryanberger.dev" },
    "description": "Personal Claude Code plugins by Bryan Berger",
    "version": "1.0.0",
    "plugins": [
      {
        "name": "snap",
        "description": "Workflow produit 5 skills (define→ticket→wireframe→develop→qa)",
        "source": {
          "source": "github",
          "repo": "BryanBerger98/snapship-plugin",
          "ref": "v1.0.0"
        },
        "version": "1.0.0",
        "author": { "name": "Bryan Berger", "email": "contact@bryanberger.dev" },
        "homepage": "https://github.com/BryanBerger98/snapship-plugin",
        "repository": "https://github.com/BryanBerger98/snapship-plugin",
        "license": "MIT",
        "keywords": ["workflow", "product-management", "tickets", "wireframes", "qa"]
      }
    ]
  }
  ```

- [x] Validation: `scripts/validate-marketplace.sh` PASS (jq syntax + per-plugin keys)
- [ ] Test local end-to-end (manuel, depuis Claude Code) :
  - `/plugin marketplace add BryanBerger98/claude-plugins`
  - `/plugin install snap@bryanberger`
  - Vérifier les 9 skills `/snap:*` disponibles dans session

## 10.3 Publication

- [x] Push GitHub `BryanBerger98/claude-plugins` (public)
- [ ] Test depuis machine vierge (manuel)
- [x] README marketplace: install + plugins listing + maintenance + validation
- [x] CI workflow `.github/workflows/validate.yml`: jq syntax + structural sanity sur push/PR (run verte)
- [x] Helper `scripts/bump-plugin.sh` pour bump `ref`/`version` par plugin

## 10.4 Annonce

- [x] README snapship-plugin: badges install + lien marketplace
- [ ] Annonce communauté CC (Discord / Reddit r/ClaudeAI / X) — manuelle

**Sortie:** `/plugin marketplace add BryanBerger98/claude-plugins` puis `/plugin install snap@bryanberger` fonctionne sur n'importe quelle session Claude Code.
