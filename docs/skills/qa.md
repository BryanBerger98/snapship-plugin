# Skill `/qa`

Validation runtime ticket(s) développé(s). Régression (scope impacted) + wireframes (Playwright vs Frame0). Cycle QA↔dev. Optionnel retrigger reviews `/develop` sur fixes.

## Frontmatter

```yaml
name: qa
description: Validation runtime ticket(s) développé(s). Régression (scope impacted) + wireframes (Playwright vs Frame0). Cycle QA↔dev. Optionnel retrigger reviews /develop sur fixes.
argument-hint: "[-a] [-r] [--qa-cycles=N] [--no-regression] [--no-wireframe-check] [--retrigger-review] [--dry-run] <ticket-id|feature-id>"
```

## Args

- `<ticket-id|feature-id>` REQUIS. Précise scope:
  - `ticket-id` (match `naming.ticket_id_regex`) → QA sur diff du commit ticket
  - `feature-id` (NN-kebab) → QA batch sur tous tickets feature `developed`

## Flags

- `-a` autonomous, `-r` resume, `-i` interactive flag config
- `--qa-cycles=N` override `qa.qa_cycles_max` pour run courant
- `--no-regression` skip regression check
- `--no-wireframe-check` skip wireframe check (sinon utilise `qa.wireframe_check.enabled`)
- `--retrigger-review` force `qa.retrigger_review=true` pour run courant

## State variables

- `{ticket_id}` ou `{feature_id}`, `{platform}`
- `{qa_cycle_count}` (compteur run-time)
- `{qa_applied_fixes}` (bool — drive retrigger_review)
- `{last_qa_result}` `{ regression: pass|fail|<list>, wireframe: pass|fail|<diff_pct>, severity }`
- `{qa_feedback_md}` markdown structuré (output `code-reviewer-qa` subagent)

## Steps

### step-00-init

- Parse args. Match ticket-id ou feature-id.
- Charge `meta.json` + `tickets.json` feature
- Détermine diff scope:
  - ticket-id → `git log --grep="{ticket_id}"` → range commits ticket
  - feature-id → range commits depuis branch divergence (`git merge-base`)
- Lance `check-mcp-required.sh qa` (validate optional MCPs nécessaires: `code-review-graph` si `regression.scope=impacted`, `playwright` si `wireframe_check.enabled=true`)
- Lance `detect-test-commands.sh` si `testing.*_command` absent

### step-01-collect (procédural — raw outputs)

- **Régression** (si `qa.regression.enabled` ET pas `--no-regression`):
  - `scope=impacted`: query `code-review-graph` MCP `get_impact_radius` sur diff → fichiers/symbols touchés. `get_affected_flows` → tests à run. Run `testing.test_command` filtré.
  - `scope=full`: run `testing.test_command` complet
  - `scope=tests-only`: run `testing.test_command` sans filtre
  - Fallback `tests-only` si `code-review-graph` absent
  - Capture: stdout, exit code, durée, list failed tests
- **Wireframe** (si `qa.wireframe_check.enabled` ET pas `--no-wireframe-check`):
  - Mode `playwright`: spawn Playwright MCP, navigate URL feature (depuis context ticket ou `meta.json.preview_url`), screenshot per écran
  - Compare vs Frame0 export PNG (`features/{id}/wireframes/*.png`) → diff structural (count buttons/inputs/sections, labels)
  - Capture: diff_pct, regions affectées, screenshots
- Persiste raw outputs dans `.claude/product/features/{id}/.qa-raw-{cycle}.json`

### step-02-interpret (subagent)

- Spawn `code-reviewer-qa` subagent avec raw outputs + context (ticket AC, wireframes liste, historique progress.md)
  - Subagent filtre flaky tests (heuristique: même test fail intermittent dans `progress.md` historique)
  - Distingue régression réelle vs brittle, decide severity per finding
  - Compose feedback markdown structuré (sections: regressions critiques, wireframe gaps, recommandations fix)
  - Retourne `{ severity, regression: pass|fail, wireframe: pass|fail, feedback_md }`
- Stocke résultat dans `{last_qa_result}` + `{qa_feedback_md}`

### step-03-fix (cycle dev)

- Loop `j = 1..qa.qa_cycles_max`:
  1. Step-01-collect + step-02-interpret
  2. **Décision exit**:
     - `regression=pass` ET (`wireframe=pass` OU wireframe disabled) ET `severity < qa.severity_threshold` → exit Phase QA OK
     - Sinon: tag `{qa_applied_fixes}=true`, spawn agent `developer` avec `{qa_feedback_md}`. Applique fixes (auto si `qa.auto_apply_qa_feedback`, sinon AskUserQuestion).
     - Re-run typecheck/lint/test entre cycles
     - **Commit fix QA atomique:** amend commit ticket si même ticket scope (`git commit --amend --no-edit`), sinon nouveau commit `fix({ticket_id}): qa - {summary}`
- Si `qa_cycles_max` atteint sans pass → applique `develop.fail_strategy` (réutilise même config car cohérence workflow)

### step-04-retrigger (opt-in)

- Si `qa.retrigger_review=true` (config ou flag `--retrigger-review`) ET `{qa_applied_fixes}=true`:
  - Re-run 3 reviewers `/develop` Phase 2 sur diff post-QA (spawn batch parallèle: technical/functional/security sur range commits ticket actualisé)
  - Si findings ≥ threshold → cycle review↔dev sur diff actuel (réutilise logique step-03a Phase 2 — implementation: `Skill develop step-03a-standalone --review-only`)
  - Après reviews OK: NE re-trigger PAS QA (boucle simple, 1 retrigger max — évite ping-pong infini)
- Si `retrigger_review=false`: skip step-04

### step-05-finish

- Update ticket plateforme: `comment <id> "QA validated"` + status (si workflow plateforme expose)
- Update `index.md` état: `qa-validated`
- Affiche résumé: cycles utilisés, severity finale, fixes appliqués
- Mode standalone: propose ticket suivant ou `/develop` PR sync si pas encore fait
- Mode batch (feature-id): résumé X/Y tickets QA-validated

## Note QA vs review fonctionnelle (`/develop`)

- Review fonctionnelle = static (lit code/diff, vérifie AC textuellement, scope conformance)
- QA = runtime (exécute tests, lance app, compare comportement vs AC + wireframes)
