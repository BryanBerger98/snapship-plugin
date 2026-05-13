# Roadmap snap

Étapes développement → publication → installation. Ordre dépendances strict.

## Phases

| # | Phase | Statut |
|---|-------|--------|
| 0 | [Setup repo](phase-00-setup.md) | livré |
| 1 | [Schemas & validation](phase-01-schemas.md) | livré |
| 2 | [Scripts `_shared/` foundation](phase-02-shared-foundation.md) | livré |
| 3 | [Adapters](phase-03-adapters.md) | livré |
| 4 | [Agents (subagents)](phase-04-agents.md) | livré |
| 5 | [Templates bundlés](phase-05-templates.md) | livré |
| 6 | [Skills (build order strict)](phase-06-skills.md) | livré |
| 7 | [Plugin manifest finalization](phase-07-plugin-manifest.md) | livré |
| 7.5 | [v0.5 `/design` + Figma + config nested](phase-07.5-v05-design-figma.md) | livré (2026-05-13) |
| 8 | [Dogfooding](phase-08-dogfooding.md) | gate ouvert |
| 9 | [Documentation utilisateur](phase-09-user-docs.md) | à venir |
| 10 | [Marketplace `bryanberger`](phase-10-marketplace.md) | à venir |
| 11 | [Install user-side (3 méthodes)](phase-11-install.md) | à venir |
| 11.5 | [v0.2 documentation refactor](phase-11.5-v02-docs-refactor.md) | livré |
| 11.6 | [v0.3+ Penpot wireframe platform](phase-11.6-v03-penpot.md) | livré |
| 12 | [Maintenance & itération](phase-12-maintenance.md) | continu |

## Critères Definition of Done (par phase)

| Phase | DoD                                                                          |
| ----- | ---------------------------------------------------------------------------- |
| 0–2   | CI green (lint + schema validation)                                          |
| 3     | Adapters dry-run + read ops fonctionnent sur 3 platforms                     |
| 4     | Chaque agent retourne JSON valide sur fixture input                          |
| 5     | Templates render sans erreur avec vars sample                                |
| 6     | E2E test suite passe par skill (mock MCP + real MCP)                         |
| 7     | `claude plugin validate .` passe sur `.claude-plugin/plugin.json`            |
| 7.5   | v0.5.0 livré : config nested + figma + /design 3 modes, tous tests verts     |
| 8     | 1 feature complète shipped via snap en dogfood (incluant /design)            |
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
| 6.3   | 1j      | frame0-helper / penpot-helper ready    |
| 6.4   | 3j      | Phase 2 review cycle complexe          |
| 6.5   | 2j      | code-review-graph + Playwright tests   |
| 7     | 0.5j    | Migration `.claude-plugin/` schema     |
| 7.5   | 11.5j   | Bridge CLI + figma_execute runtime, scope /design ambitieux |
| 8     | 2j      | Bugs prod réels                        |
| 9     | 1.5j    | Screencast prod                        |
| 10    | 1j      | Repo `bryanberger/claude-plugins` + CI |
| 11    | 0.5j    | -                                      |
| 12    | continu | Bandwidth maintainer                   |

**Total v0.1.0:** ~22-25j dev focus (≈ +0.5j vs avant pour setup marketplace `bryanberger`).

**Total v0.5.0** (avec Phase 7.5 livrée avant dogfooding) : ~33-37j dev focus.
