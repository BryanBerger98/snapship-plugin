# Changelog

All notable changes to artysan-plugin documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the
project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Plugin manifest at `.claude-plugin/plugin.json` (Claude Code schema-conforme).
- `.mcp.json` racine bundle `code-review-graph` MCP — auto-start quand plugin activé.
- `NOTICE` documentant attributions community MCPs (code-review-graph, affine-mcp-server, frame0-mcp-server, playwright-mcp).
- `/qa` skill complet: pipeline 6 étapes (init→collect→interpret→fix→retrigger→finish), regression scope=impacted via code-review-graph (fallback tests-only), wireframe diff Playwright vs Frame0 PNG, code-reviewer-qa agent, dev↔qa cycle bounded, opt-in retrigger des 3 reviewers /develop.
- `/develop` skill complet: standalone + loop session/daemon, 3 reviewers parallèles (technical/functional/security), atomic commits, fail_strategy (next-ticket/stop/retry+fallback).
- `/wireframe` skill complet: filtre UI tickets, génération multi-écrans Frame0, AFFiNE gallery embed.
- `/ticket` skill complet: décomposition PRD → tickets, enrichissement explore-codebase, push plateforme adapter (github/gitlab/jira).
- `/define` skill complet: setup wizard initial, brainstorm PRD interactif, AFFiNE storage.
- 4 reviewer agents: technical, functional, security, qa.
- E2E tests: define, ticket, wireframe, develop, qa (135 deterministic checks).

### Changed

- `tickets.json` schema étendu pour cycle /qa: status enum + `qa-validated`, `acceptance_criteria.ac_id`, `qa_cycles_used`, `qa_last_severity`, `qa_last_flaky_verdict`, `qa_blocked`, `qa_retriggered`, `qa_retrigger_severity`, `qa_retrigger_verdicts`, `updated_at`.

### Removed

- Legacy `plugin.json` racine remplacé par `.claude-plugin/plugin.json`.
- Champs custom invalides (`skills_path`, `agents_path`, `shared_scripts_path`, `schemas_path`, `templates_path`, `commands` array d'objets, `mcp_servers`) — non supportés par schéma plugin CC.

## [0.1.0] — TBD

Premier scaffold pré-marketplace. Cible: validation interne projet pilote (Phase 8 dogfooding) avant publication marketplace `bryanberger/claude-plugins`.
