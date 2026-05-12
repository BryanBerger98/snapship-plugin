# Phase 6 — Skills (build order strict)

**Objectif:** 5 skills opérationnels, validés bout en bout.

## 6.1 `/define`

- [x] step-00 → step-05 (chaque step = 1 fichier MD frontmatter `next_step`)
- [x] Détection `has_codebase` + branche green-field
- [x] AskUserQuestion progressive vision → features
- [x] Push PRD AFFiNE via docs-adapter
- [x] Resume `-r` partial-match
- [x] Test E2E: green-field + projet existant

## 6.2 `/ticket`

- [ ] step-00 → step-06
- [x] Decompose stories atomiques (5-30min, 1-5 fichiers)
- [x] Enrich parallel agents (explore-codebase, explore-docs, websearch)
- [x] Format adaptatif platform (templates ticket-*.md)
- [x] Push via tickets-adapter (MCP > CLI fallback)
- [x] Test E2E: 3 platforms (gh/glab/jira)

## 6.3 `/wireframe`

- [x] step-00 → step-04
- [x] Filter tickets UI (heuristique mots-clés)
- [x] Loop design via helper résolu depuis `wireframes.platform` (frame0 | penpot) — shapes + export asset unique (format depuis config)
- [x] Préflight platform-specific (Frame0 desktop HTTP API reachable / Penpot file binding via `get-current-file` + AskUserQuestion)
- [x] Page AFFiNE Gallery (embed images via blob upload)
- [x] Update tickets liens gallery
- [x] Test E2E: 3 écrans avec états (frame0 + penpot)

## 6.4 `/develop`

- [x] step-00 → step-05
- [x] step-03a Phase 1 (analyze/plan/execute/validate, 4 fichiers)
- [x] step-03a Phase 2 (3 reviewers parallèles via 1 message N Agent calls)
- [x] Severity scale + early stop logic
- [x] fail_strategy (next-ticket/stop/retry)
- [x] Commit atomique (1 ticket = 1 commit, amend fixes)
- [x] step-03b loop session
- [x] step-03c daemon setup (génère script, no auto-launch)
- [x] Branche idempotente (`git rev-parse --verify`)
- [x] Test E2E: standalone + session + daemon dry-run

## 6.5 `/qa`

- [x] step-00 → step-05
- [x] Régression scope=impacted via code-review-graph (fallback tests-only)
- [x] Wireframe check Playwright vs Frame0 PNG (structural-diff)
- [x] Subagent code-reviewer-qa + flaky detection
- [x] Cycle dev↔qa avec amend commit
- [x] Retrigger reviews opt-in (1 retrigger max)
- [x] Test E2E: ticket avec régression + wireframe gap

**Sortie:** 5 skills passent E2E sur fixture project.
