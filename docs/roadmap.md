# Roadmap artysan

Étapes développement → publication → installation. Ordre dépendances strict.

## Phase 0 — Setup repo

**Objectif:** scaffolding plugin + tooling dev.

- [x] Init repo `artysan` (git, license MIT, README minimal)
- [x] Créer arbo squelette: `skills/`, `agents/`, `skills/_shared/`, `skills/_shared/templates/`, `skills/_shared/schemas/`
- [x] `.gitignore`: `_shared/telemetry.log*`, `.config-resolved.json`, `.qa-raw-*.json`
- [x] `plugin.json` brouillon (name, version 0.1.0, paths)
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
- [ ] `frame0-helper.sh` — wrapper batch ops Frame0 MCP
- [ ] Mode `--dry-run` env var respecté par tous adapters (write ops → log skip)

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

**Objectif:** `plugin.json` final + métadonnées marketplace.

- [ ] `plugin.json`: name, version, description, author, license, repo URL
- [ ] Paths: `skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`
- [ ] Section `mcp_servers` (required + optional list)
- [ ] Section `commands` (5 slash commands déclarés)
- [ ] CHANGELOG.md (semver)
- [ ] LICENSE + NOTICE (attributions community MCPs)

**Sortie:** plugin chargeable via clone manuel `.claude/plugins/`.

## Phase 8 — Dogfooding

**Objectif:** valider sur projet réel avant marketplace.

- [ ] Choisir projet pilote (green-field idéal: app side-project user)
- [ ] Run cycle complet `/define` → `/qa` sur 1-2 features réelles
- [ ] Capture friction points (steps lents, prompts ambigus, échecs MCP)
- [ ] Itérer fixes critiques (P0)
- [ ] Telemetry analyse: identifier cycles fréquents, retries, durées

**Sortie:** v0.1.0-rc validée prod use, backlog P1+ ouvert.

## Phase 9 — Documentation utilisateur

**Objectif:** docs install + usage public.

- [ ] README.md repo (quickstart 5 min)
- [ ] `docs/install.md` (marketplace + manuel + projet-scoped)
- [ ] `docs/getting-started.md` (premier `/define` walkthrough)
- [ ] `docs/troubleshooting.md` (auth MCP, conflicts, resume)
- [ ] `docs/configuration.md` (référence `artysan.config.json` complète)
- [ ] Screencast court (asciinema) flux `/define` → `/develop` → `/qa`
- [ ] Migration guide si breaking changes futurs

**Sortie:** user autonome install + premier run sans support.

## Phase 10 — Publication marketplace

**Objectif:** plugin discoverable via Claude Code marketplace officiel.

- [ ] Submit plugin marketplace (process officiel CC)
  - Repo public + tags semver
  - `plugin.json` valide
  - License OSI-approved
- [ ] Tag release v0.1.0 (`git tag -a v0.1.0 -m "..."` + push)
- [ ] GitHub Release notes (CHANGELOG.md extrait)
- [ ] Annonce: README badge, social, communauté CC
- [ ] Setup issue templates (bug, feature, question)

**Sortie:** `/plugin install artysan` fonctionne sur CC user.

## Phase 11 — Install user-side (3 méthodes)

### 11.1 Marketplace (recommandé)

```bash
# Dans Claude Code session
/plugin install artysan
# Skills + agents + scripts + schemas + templates copiés ~/.claude/
```

### 11.2 Clone manuel global

```bash
git clone https://github.com/<org>/artysan ~/.claude/plugins/artysan
# Plugin auto-loaded au prochain démarrage CC
```

### 11.3 Projet-scoped

```bash
git clone https://github.com/<org>/artysan .claude/plugins/artysan
# Activé uniquement dans ce projet
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

**Sortie:** plugin maintenu, communauté contribue (PRs).

## Critères Definition of Done (par phase)

| Phase    | DoD                                                                          |
| -------- | ---------------------------------------------------------------------------- |
| 0–2      | CI green (lint + schema validation)                                          |
| 3        | Adapters dry-run + read ops fonctionnent sur 3 platforms                     |
| 4        | Chaque agent retourne JSON valide sur fixture input                          |
| 5        | Templates render sans erreur avec vars sample                                |
| 6        | E2E test suite passe par skill (mock MCP + real MCP)                         |
| 7        | `plugin.json` valide CC marketplace schema                                   |
| 8        | 1 feature complète shipped via artysan en dogfood                            |
| 9        | User non-impliqué installe + run premier `/define` sans aide                 |
| 10       | Plugin listé marketplace, install command fonctionne                         |
| 11       | 3 méthodes install testées (marketplace + clone global + projet)             |
| 12       | Cadence release tenue, telemetry-driven priorities                           |

## Estimation effort (indicatif)

| Phase | Effort         | Bloquants critiques                    |
| ----- | -------------- | -------------------------------------- |
| 0     | 0.5j           | -                                      |
| 1     | 1j             | Schemas exhaustifs                     |
| 2     | 3j             | load-config robuste                    |
| 3     | 2j             | MCP adapters fiables                   |
| 4     | 2j             | Format JSON return strict              |
| 5     | 1j             | -                                      |
| 6.1   | 1j             | docs-adapter ready                     |
| 6.2   | 1.5j           | tickets-adapter ready                  |
| 6.3   | 1j             | frame0-helper ready                    |
| 6.4   | 3j             | Phase 2 review cycle complexe          |
| 6.5   | 2j             | code-review-graph + Playwright tests   |
| 7     | 0.5j           | -                                      |
| 8     | 2j             | Bugs prod réels                        |
| 9     | 1.5j           | Screencast prod                        |
| 10    | 0.5j           | Process marketplace CC                 |
| 11    | 0.5j           | -                                      |
| 12    | continu        | Bandwidth maintainer                   |

**Total v0.1.0:** ~22-25j dev focus.
