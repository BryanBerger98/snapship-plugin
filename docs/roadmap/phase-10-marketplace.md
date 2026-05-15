# Phase 10 — Marketplace `bryanberger`

**Objectif:** héberger snap (et futurs plugins) dans une marketplace personnelle GitHub découvrable via `/plugin marketplace add bryanberger/claude-plugins`.

> Claude Code n'a pas de marketplace centrale Anthropic — chaque créateur publie via un repo GitHub contenant `.claude-plugin/marketplace.json`. Nom `bryanberger` libre (liste réservée complète: `claude-code-marketplace`, `claude-code-plugins`, `claude-plugins-official`, `anthropic-marketplace`, `anthropic-plugins`, `agent-skills`, `knowledge-work-plugins`, `life-sciences`).
>
> Source types acceptés: relative path (string), `github` (`{source:"github", repo, ref|sha}`), `url` (git URL), `git-subdir` (sous-dossier d'un repo git), `npm`. On utilise `github` avec `ref` = tag release.

## 10.1 Préparation plugin

- [ ] Tag release `v1.0.0` sur repo plugin (`git tag -a v1.0.0 -m "..." && git push --tags`)
- [ ] GitHub Release notes (extrait CHANGELOG.md)
- [ ] Setup issue templates (`bug.yml`, `feature.yml`, `question.yml`) dans `.github/ISSUE_TEMPLATE/`

## 10.2 Création marketplace repo

- [ ] Créer repo public `bryanberger/claude-plugins` (license MIT, README quickstart)
- [ ] Arbo:

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

- [ ] Validation: `claude plugin validate .` passe sans warning
- [ ] Test local end-to-end:
  - `/plugin marketplace add ./claude-plugins`
  - `/plugin install snap@bryanberger`
  - Vérifier 5 skills disponibles dans session Claude Code

## 10.3 Publication

- [ ] Push GitHub `bryanberger/claude-plugins` (public)
- [ ] Test depuis machine vierge: `/plugin marketplace add bryanberger/claude-plugins`
- [ ] README marketplace: badge install, lien snap, instructions ajout marketplaces additionnels
- [ ] CI workflow `validate-marketplace.yml`: `claude plugin validate .` sur push/PR
- [ ] Auto-bump `marketplace.json` `ref`/`version` à chaque release snap (script `bump-marketplace.sh` ou GitHub Action workflow_dispatch)

## 10.4 Annonce

- [ ] README snapship-plugin: badge install + lien marketplace
- [ ] Annonce communauté CC (Discord / Reddit r/ClaudeAI / X)

**Sortie:** `/plugin marketplace add bryanberger/claude-plugins` puis `/plugin install snap@bryanberger` fonctionne sur n'importe quelle session Claude Code.
