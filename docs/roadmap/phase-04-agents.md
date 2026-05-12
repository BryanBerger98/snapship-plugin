# Phase 4 — Agents (subagents)

**Objectif:** agents `.claude/agents/` invoqués par skills via Agent tool.

- [x] `snap-code-reviewer-technical` (clean code, conventions repo, lint/style)
- [x] `snap-code-reviewer-functional` (AC, wireframes match, scope conformance)
- [x] `snap-code-reviewer-security` (OWASP, secrets, injection, auth, deps)
- [x] `snap-code-reviewer-qa` (interpret raw outputs, flaky detection, severity)
- [x] `snap-developer` (applique aggregated_feedback)
- [x] Format retour JSON fence `{ severity, feedback_md }` (parse-able regex+jq)

**Sortie:** agents testables isolément (input fixture → output JSON valide).
