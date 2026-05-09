# Roadmap artysan

Étapes développement → publication → installation. Ordre dépendances strict.

## Phase 0 — Setup repo

**Objectif:** scaffolding plugin + tooling dev.

- [x] Init repo `artysan` (git, license MIT, README minimal)
- [x] Créer arbo squelette: `skills/`, `agents/`, `skills/_shared/`, `skills/_shared/templates/`, `skills/_shared/schemas/`
- [x] `.gitignore`: `_shared/telemetry.log*`, `.config-resolved.json`, `.qa-raw-*.json`
- [x] `plugin.json` brouillon (name, version 0.1.0, paths) — migration vers `.claude-plugin/plugin.json` en Phase 7 (schema officiel CC)
- [x] CI minimal: lint shell (`shellcheck`), validate JSON Schemas (`ajv-cli`), markdown lint
- [x] Structure docs `artysan/` copiée depuis ce dossier (source vérité)

**Sortie:** repo public clone-able, structure vide validable CI.

## Phase 1 — Schemas & validation

**Objectif:** schemas JSON utilisés par toute config + meta + tickets.

- [x] `_shared/schemas/config.schema.json` — couvre toutes sections `artysan.config.json` (repository, tickets+jira nested, documentation, wireframes, testing, naming, ai, develop, qa, lifecycle_scripts, defaults)
- [x] `_shared/schemas/meta.schema.json` — feature `meta.json` (feature_id, affine_page_id, branch_name, etc.)
- [x] `_shared/schemas/tickets.schema.json` — cache `tickets.json`
- [x] Tests fixtures valides + invalides par schema
- [x] CI exécute validation sur fixtures

**Sortie:** schemas testés, base solide load-config.

## Phase 2 — Scripts `_shared/` foundation

**Objectif:** scripts socle utilisés par tous skills.

Ordre dépendances:

1. [x] `load-config.sh` (lit config + defaults + valide schema)
2. [x] `setup-product-dir.sh` (init `.claude/product/`)
3. [x] `update-index.sh` + `update-progress.sh` (state tracking)
4. [x] `telemetry.sh` (NDJSON append + rotation)
5. [x] `ask-or-default.sh` (wrapper auto-mode)
6. [x] `apply-naming.sh` (render templates branch/commit)
7. [x] `detect-test-commands.sh` (auto-detect test/lint)
8. [x] `check-mcp-required.sh` (validate MCPs + conflict resolution)
9. [x] `detect-platforms.sh` (runtime check auth)
10. [x] `setup-config.sh` (interactive wizard initial)
11. [x] `run-lifecycle-script.sh` (custom hooks workflow)

**Sortie:** scripts unitaires testables (`bats` shell tests recommandé).

## Phase 3 — Adapters

**Objectif:** abstraction MCP/CLI plateformes externes.

- [x] `docs-adapter.sh` — AFFiNE + Notion (get/create/apply-template/upload-blob/update/search)
- [x] `tickets-adapter.sh` — GitHub/GitLab/JIRA (create/get/update/comment/list)
- [x] `frame0-helper.sh` — wrapper batch ops Frame0 MCP
- [x] Mode `--dry-run` env var respecté par tous adapters (write ops → log skip)

**Sortie:** adapters interchangeables, write ops idempotentes.

## Phase 4 — Agents (subagents)

**Objectif:** agents `.claude/agents/` invoqués par skills via Agent tool.

- [ ] `code-reviewer-technical` (clean code, conventions repo, lint/style)
- [ ] `code-reviewer-functional` (AC, wireframes match, scope conformance)
- [ ] `code-reviewer-security` (OWASP, secrets, injection, auth, deps)
- [ ] `code-reviewer-qa` (interpret raw outputs, flaky detection, severity)
- [ ] `developer` (applique aggregated_feedback)
- [ ] Format retour JSON fence `{ severity, feedback_md }` (parse-able regex+jq)

**Sortie:** agents testables isolément (input fixture → output JSON valide).

## Phase 5 — Templates bundlés

**Objectif:** templates markdown + bash bundlés dans plugin.

- [ ] `templates/docs-defaults/prd-global.md`
- [ ] `templates/docs-defaults/prd-feature.md`
- [ ] `templates/docs-defaults/wireframes-gallery.md`
- [ ] `templates/pr-default.md` (fallback PR template)
- [ ] `templates/daemon.sh.tpl` (loop daemon)
- [ ] `templates/session-start-hook.sh.tpl` (opt-in pre-load)
- [ ] `templates/ticket-{github,gitlab,jira}.md` (format adaptatif)

**Sortie:** templates valides, variables documentées par template.

## Phase 6 — Skills (build order strict)

**Objectif:** 5 skills opérationnels, validés bout en bout.

### 6.1 `/define`

- [ ] step-00 → step-05 (chaque step = 1 fichier MD frontmatter `next_step`)
- [ ] Détection `has_codebase` + branche green-field
- [ ] AskUserQuestion progressive vision → features
- [ ] Push PRD AFFiNE via docs-adapter
- [ ] Resume `-r` partial-match
- [ ] Test E2E: green-field + projet existant

### 6.2 `/ticket`

- [ ] step-00 → step-06
- [ ] Decompose stories atomiques (5-30min, 1-5 fichiers)
- [ ] Enrich parallel agents (explore-codebase, explore-docs, websearch)
- [ ] Format adaptatif platform (templates ticket-*.md)
- [ ] Push via tickets-adapter (MCP > CLI fallback)
- [ ] Test E2E: 3 platforms (gh/glab/jira)

### 6.3 `/wireframe`

- [ ] step-00 → step-04
- [ ] Filter tickets UI (heuristique mots-clés)
- [ ] Loop design Frame0 MCP (shapes + export PNG)
- [ ] Page AFFiNE Gallery (embed images via blob upload)
- [ ] Update tickets liens gallery
- [ ] Test E2E: 3 écrans avec états

### 6.4 `/develop`

- [ ] step-00 → step-05
- [ ] step-03a Phase 1 (analyze/plan/execute/validate, 4 fichiers)
- [ ] step-03a Phase 2 (3 reviewers parallèles via 1 message N Agent calls)
- [ ] Severity scale + early stop logic
- [ ] fail_strategy (next-ticket/stop/retry)
- [ ] Commit atomique (1 ticket = 1 commit, amend fixes)
- [ ] step-03b loop session
- [ ] step-03c daemon setup (génère script, no auto-launch)
- [ ] Branche idempotente (`git rev-parse --verify`)
- [ ] Test E2E: standalone + session + daemon dry-run

### 6.5 `/qa`

- [ ] step-00 → step-05
- [ ] Régression scope=impacted via code-review-graph (fallback tests-only)
- [ ] Wireframe check Playwright vs Frame0 PNG (structural-diff)
- [ ] Subagent code-reviewer-qa + flaky detection
- [ ] Cycle dev↔qa avec amend commit
- [ ] Retrigger reviews opt-in (1 retrigger max)
- [ ] Test E2E: ticket avec régression + wireframe gap

**Sortie:** 5 skills passent E2E sur fixture project.

## Phase 7 — Plugin manifest finalization

**Objectif:** `.claude-plugin/plugin.json` final + structure conforme schema officiel Claude Code.

- [ ] Migrer `plugin.json` racine → `.claude-plugin/plugin.json`
- [ ] Champs requis schema CC: `name` (kebab-case), `version` (semver `MAJOR.MINOR.PATCH`), `description`, `author{name,email}`, `homepage`, `repository`, `license`, `keywords`
- [ ] Déclarer paths: `skills`, `agents`, `commands` (relatifs racine plugin)
- [ ] MCP servers: `.mcp.json` racine plugin (required + optional list)
- [ ] Hooks: `hooks/hooks.json` (si nécessaire)
- [ ] Validation: `claude plugin validate .` passe sans warning
- [ ] Test install local: `/plugin marketplace add ./` → `/plugin install artysan@<local-name>`
- [ ] CHANGELOG.md (Keep-a-Changelog, semver)
- [ ] LICENSE + NOTICE (attributions community MCPs)

**Sortie:** plugin valide schema CC, installable manuellement, prêt marketplace.

## Phase 8 — Dogfooding

**Objectif:** valider sur projet réel avant publication marketplace.

- [ ] Choisir projet pilote (green-field idéal: app side-project user)
- [ ] Run cycle complet `/define` → `/qa` sur 1-2 features réelles
- [ ] Capture friction points (steps lents, prompts ambigus, échecs MCP)
- [ ] Itérer fixes critiques (P0)
- [ ] Telemetry analyse: identifier cycles fréquents, retries, durées

**Sortie:** v0.1.0-rc validée prod use, backlog P1+ ouvert.

## Phase 9 — Documentation utilisateur

**Objectif:** docs install + usage public.

- [ ] README.md repo (quickstart 5 min)
- [ ] `docs/install.md` (marketplace `bryanberger` + clone manuel + projet-scoped)
- [ ] `docs/getting-started.md` (premier `/define` walkthrough)
- [ ] `docs/troubleshooting.md` (auth MCP, conflicts, resume)
- [ ] `docs/configuration.md` (référence `artysan.config.json` complète)
- [ ] Screencast court (asciinema) flux `/define` → `/develop` → `/qa`
- [ ] Migration guide si breaking changes futurs

**Sortie:** user autonome install + premier run sans support.

## Phase 10 — Marketplace `bryanberger`

**Objectif:** héberger artysan (et futurs plugins) dans une marketplace personnelle GitHub découvrable via `/plugin marketplace add bryanberger/claude-plugins`.

> Claude Code n'a pas de marketplace centrale Anthropic — chaque créateur publie via un repo GitHub contenant `.claude-plugin/marketplace.json`. Nom `bryanberger` libre (pas dans la liste réservée: `claude-plugins-official`, `claude-code-marketplace`, `anthropic-marketplace`, `agent-skills`).

### 10.1 Préparation plugin

- [ ] Tag release `v0.1.0` sur repo plugin (`git tag -a v0.1.0 -m "..." && git push --tags`)
- [ ] GitHub Release notes (extrait CHANGELOG.md)
- [ ] Setup issue templates (`bug.yml`, `feature.yml`, `question.yml`) dans `.github/ISSUE_TEMPLATE/`

### 10.2 Création marketplace repo

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
        "name": "artysan",
        "description": "Workflow produit 5 skills (define→ticket→wireframe→develop→qa)",
        "source": {
          "source": "github",
          "repo": "BryanBerger98/artysan-plugin",
          "ref": "v0.1.0"
        },
        "version": "0.1.0",
        "author": { "name": "Bryan Berger", "email": "contact@bryanberger.dev" },
        "homepage": "https://github.com/BryanBerger98/artysan-plugin",
        "repository": "https://github.com/BryanBerger98/artysan-plugin",
        "license": "MIT",
        "keywords": ["workflow", "product-management", "tickets", "wireframes", "qa"]
      }
    ]
  }
  ```

- [ ] Validation: `claude plugin validate .` passe sans warning
- [ ] Test local end-to-end:
  - `/plugin marketplace add ./claude-plugins`
  - `/plugin install artysan@bryanberger`
  - Vérifier 5 skills disponibles dans session Claude Code

### 10.3 Publication

- [ ] Push GitHub `bryanberger/claude-plugins` (public)
- [ ] Test depuis machine vierge: `/plugin marketplace add bryanberger/claude-plugins`
- [ ] README marketplace: badge install, lien artysan, instructions ajout marketplaces additionnels
- [ ] CI workflow `validate-marketplace.yml`: `claude plugin validate .` sur push/PR
- [ ] Auto-bump `marketplace.json` `ref`/`version` à chaque release artysan (script `bump-marketplace.sh` ou GitHub Action workflow_dispatch)

### 10.4 Annonce

- [ ] README artysan-plugin: badge install + lien marketplace
- [ ] Annonce communauté CC (Discord / Reddit r/ClaudeAI / X)

**Sortie:** `/plugin marketplace add bryanberger/claude-plugins` puis `/plugin install artysan@bryanberger` fonctionne sur n'importe quelle session Claude Code.

## Phase 11 — Install user-side (3 méthodes)

### 11.1 Marketplace `bryanberger` (recommandé)

```bash
# Dans Claude Code session
/plugin marketplace add bryanberger/claude-plugins
/plugin install artysan@bryanberger
# Skills + agents + scripts + schemas + templates copiés ~/.claude/
```

Auto-update opt-in via `/plugin` → onglet Marketplaces.

### 11.2 Clone manuel global

```bash
git clone https://github.com/BryanBerger98/artysan-plugin ~/.claude/plugins/artysan
# Plugin auto-loaded au prochain démarrage CC
```

### 11.3 Projet-scoped (équipe)

```bash
# Dans repo projet, ajouter à .claude/settings.json:
{
  "extraKnownMarketplaces": {
    "bryanberger": { "source": { "source": "github", "repo": "bryanberger/claude-plugins" } }
  },
  "enabledPlugins": { "artysan@bryanberger": true }
}
# Membres équipe: prompt install au prochain démarrage CC dans le projet
```

### 11.4 Setup premier projet

```bash
cd <mon-projet>
claude
# Dans session:
/define "feature description"
# → setup-config.sh interactive wizard détecte:
#   - .git/config (platform, url)
#   - MCP servers actifs (affine, frame0, etc.)
#   - test commands (package.json, Cargo.toml, etc.)
# → écrit artysan.config.json racine projet
# → continue step-01-discover ou green-field
```

**Sortie:** user productif < 10 min après install.

## Phase 12 — Maintenance & itération

**Objectif:** lifecycle post-v1.

- [ ] Bug triage (issues GitHub)
- [ ] Telemetry analyse mensuelle (steps lents, cycles dépassés)
- [ ] Patch releases (v0.1.x) — bugs MCP, edge cases
- [ ] Minor releases (v0.2+) — nouvelles features (templates additionnels, nouveaux adapters platforms)
- [ ] Major release (v1.0) — API stable, breaking changes documentés
- [ ] Compatibilité MCP versions (track upstream changes affine/frame0/playwright)
- [ ] Sync `bryanberger/claude-plugins` `marketplace.json` à chaque release artysan (`ref` → nouveau tag, `version` bumpée)

**Sortie:** plugin maintenu, communauté contribue (PRs).

## Critères Definition of Done (par phase)

| Phase | DoD                                                                          |
| ----- | ---------------------------------------------------------------------------- |
| 0–2   | CI green (lint + schema validation)                                          |
| 3     | Adapters dry-run + read ops fonctionnent sur 3 platforms                     |
| 4     | Chaque agent retourne JSON valide sur fixture input                          |
| 5     | Templates render sans erreur avec vars sample                                |
| 6     | E2E test suite passe par skill (mock MCP + real MCP)                         |
| 7     | `claude plugin validate .` passe sur `.claude-plugin/plugin.json`            |
| 8     | 1 feature complète shipped via artysan en dogfood                            |
| 9     | User non-impliqué installe + run premier `/define` sans aide                 |
| 10    | `/plugin marketplace add bryanberger/claude-plugins` + install fonctionne    |
| 11    | 3 méthodes install testées (marketplace bryanberger + clone global + projet) |
| 12    | Cadence release tenue, telemetry-driven priorities                           |

## Estimation effort (indicatif)

| Phase | Effort  | Bloquants critiques                    |
| ----- | ------- | -------------------------------------- |
| 0     | 0.5j    | -                                      |
| 1     | 1j      | Schemas exhaustifs                     |
| 2     | 3j      | load-config robuste                    |
| 3     | 2j      | MCP adapters fiables                   |
| 4     | 2j      | Format JSON return strict              |
| 5     | 1j      | -                                      |
| 6.1   | 1j      | docs-adapter ready                     |
| 6.2   | 1.5j    | tickets-adapter ready                  |
| 6.3   | 1j      | frame0-helper ready                    |
| 6.4   | 3j      | Phase 2 review cycle complexe          |
| 6.5   | 2j      | code-review-graph + Playwright tests   |
| 7     | 0.5j    | Migration `.claude-plugin/` schema     |
| 8     | 2j      | Bugs prod réels                        |
| 9     | 1.5j    | Screencast prod                        |
| 10    | 1j      | Repo `bryanberger/claude-plugins` + CI |
| 11    | 0.5j    | -                                      |
| 12    | continu | Bandwidth maintainer                   |

**Total v0.1.0:** ~22-25j dev focus (≈ +0.5j vs avant pour setup marketplace `bryanberger`).
