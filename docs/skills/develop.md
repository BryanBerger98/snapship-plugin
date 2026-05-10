# Skill `/develop`

Développe ticket(s). Mode standalone sur 1 ticket (cycle dev/review interne), mode loop séquentiel ou daemon pour epic/feature.

## Frontmatter

```yaml
name: develop
description: Développe ticket(s). Mode standalone sur 1 ticket (cycle dev/review interne), mode loop séquentiel ou daemon pour epic/feature.
argument-hint: "[-a] [-r] [-s] [-b] [--loop=session|daemon] [-n <max>] [--dry-run] <ticket-id|feature-id>"
```

## Flags

- `-a` autonomous, `-i` interactif strict, `-r {task-id}` resume, `-b` browse-only (no execute)
- `-s` save mode (force persist intermediate states), `-e` economy mode (low-token output)
- `--loop=session` boucle séquentielle même session
- `--loop=daemon` génère script daemon, user lance manuellement
- `-n <max>` limite itérations en mode loop
- `--review-cycles=N` override `develop.review_cycles_max` pour run courant. `0` = skip review.
- `--no-review` skip cycle review↔dev. Équivalent `--review-cycles=0`. Pour fix triviaux/hotfix.
- `--no-tech` / `--no-functional` / `--no-security` désactive un type de review pour run courant
- `--review-only` skip code (Phase 1), run reviews sur diff existant (utile post-QA retrigger ou re-validation)

## State variables

- `{task_description}`, `{acceptance_criteria}`, `{context}` (issus du ticket + PRD)
- `{auto_mode}`, `{interactive_strict}`, `{save_mode}`, `{economy_mode}`, `{branch_mode}`
- `{ticket_id}`, `{feature_id}`, `{platform}`
- `{loop_mode}` = `none|session|daemon`
- `{max_iterations}` (depuis `-n`)
- `{review_cycle_count}` (compteur run-time)
- `{last_review_severities}` map `{technical, functional, security}` → `none|info|minor|major|critical`
- `{aggregated_feedback}` markdown aggrégé (sections technical/functional/security concaténées) du dernier batch — composé depuis les `feedback_md` retournés par chaque subagent reviewer

## Steps

### step-00-init

Parse. Détecte `<arg>`:

- Match `naming.ticket_id_regex` → standalone (1 ticket)
- Format `NN-kebab` (ex: `01-auth`) → loop (demande mode si pas spécifié)
- Lance `check-mcp-required.sh develop` (validate MCPs)
- Lance `detect-platforms.sh --section=tickets` (vérif auth)
- Lance `detect-test-commands.sh` si `testing.*_command` absent

### step-01-fetch

Récupère ticket(s) via MCP/CLI. Cache dans `.claude/product/features/{id}/tickets.json`.

### step-02-prepare

Convertit ticket(s) → state variables + crée branche:

- Title + description → `{task_description}`
- AC ticket → `{acceptance_criteria}`
- Tech notes → context initial
- Wireframe link → ajouté au context
- **Lit page AFFiNE feature** (PRD feature) via MCP depuis `meta.json.affine_page_id` → ajoute contexte produit/business à `{context}`
- **Branch creation (idempotent):** si `defaults.branch_mode=true`:
  - Render branch via `apply-naming.sh branch` avec `naming.branch_pattern` + context (type, ticket_id, slug)
  - Vérifie `{rendered}` pas dans `repository.protected_branches` → erreur si oui
  - Idempotence:
    ```bash
    if git rev-parse --verify "{rendered}" >/dev/null 2>&1; then
      git checkout "{rendered}"
    else
      git checkout -b "{rendered}"
    fi
    ```
  - Persiste dans `meta.json.branch_name`
  - Si `branch_mode=false` → skip, dev sur branche courante

### step-03a-standalone (1 ticket) — 2 phases séquentielles

#### Phase 1: Code (workflow inline analyze/plan/execute/validate)

- Skip si `--review-only`
- 4 sub-steps natifs séquentiels (1 fichier MD par sub-step, frontmatter `next_step`):
  1. **analyze** — lit ticket + AC + context PRD + wireframe lié si présent. Identifie fichiers impactés (via `code-review-graph` MCP `get_impact_radius` si dispo, sinon `semantic_search_nodes`)
  2. **plan** — décompose en steps techniques. AskUserQuestion A/P/C sauf `-a`
  3. **execute** — applique changements (Edit/Write). Stage continu
  4. **validate** — `testing.*_command` (typecheck/lint/test). AC ticket cochés. Itère si fail (max 3 retry, sinon escalate)

#### Phase 2: Cycle review↔developer (3 reviews spécialisées en parallèle)

- Skip si `--no-review` ou `--review-cycles=0`
- Reviews actives = `[technical, functional, security]` moins types désactivés via flags `--no-tech`/`--no-functional`/`--no-security`
- Loop `i = 1..develop.review_cycles_max`:
  1. **Spawn batch parallèle via Agent tool** (1 message contenant N Agent tool calls = parallel execution native CC, context isolé par fork). Sur diff courant:
     - `Agent(subagent_type: "snap-code-reviewer-technical", description: ...)` → severity tech (clean code, conventions repo, lint/style)
     - `Agent(subagent_type: "snap-code-reviewer-functional", description: ...)` → severity fonctionnelle (AC ticket cochés? matche description? wireframes respectés?)
     - `Agent(subagent_type: "snap-code-reviewer-security", description: ...)` → severity sécu (OWASP, secrets, injection, auth, dépendances)
     - Chaque agent retourne JSON fence final `{ severity, feedback_md }` — skill parse via regex + jq (voir Subagent return format)
  2. **Décision exit** — passe si pour **chaque type actif**:
     - `severity < develop.reviews.{type}.severity_threshold`
     → exit OK (early stop, premier batch clean accepté)
  3. **Sinon dev fix combiné**: skill compose `{aggregated_feedback}` = concat sections `technical/functional/security` depuis `feedback_md` retournés. Spawn agent `developer` avec `{aggregated_feedback}`. Applique fixes (auto si `auto_apply_review_feedback`, sinon AskUserQuestion).
  4. Re-run typecheck/lint/test (config `testing.*`)
- Si max atteint sans approval → applique `develop.fail_strategy`:
  - `next-ticket`: skip + log par-type severities, passe au suivant (mode loop)
  - `stop`: arrête workflow, dump `{aggregated_feedback}` dans `progress.md`
  - `retry`: relance step-03a Phase 1 depuis analyze avec context augmenté (max 1 retry):
    - Inject `{previous_attempt_feedback}` = `{aggregated_feedback}` du run précédent
    - Inject flag `{retry_strategy_hint}` = "Approche précédente n'a pas convergé (max cycles atteint). Explore alternative: changer pattern/architecture/séparation responsabilités. Ne pas répéter solution échouée."
    - `{retry_count}` incrémenté, persisté dans progress.md
    - Si retry échoue aussi → fallback vers `next-ticket` ou `stop` (selon flag `--retry-fallback`, default: `stop`)

**Severity scale (commune 3 reviews):** `info` < `minor` < `major` < `critical`. `none` = pas de finding.

**Validation runtime (régression + wireframes):** déléguée à skill `/qa` séparée, lancée après `/develop` (voir [qa.md](qa.md)). Step-05-finish suggère `/qa {ticket-id}`.

#### Commit atomique post-Phase 2 (1 ticket = 1 commit)

À la fin du step-03a (Phase 2 OK), skill commit le diff de manière atomique:

- Build message via `apply-naming.sh commit` avec `naming.commit_pattern` + context (`type` inféré du ticket type, `scope` du ticket, `message` = title)
- Stage diff workflow uniquement: `git add -A` du scope diff (skill track fichiers touchés depuis Phase 1)
- `git commit` avec message rendu
- 1 commit = 1 ticket. Pas de squash. Si Phase 2 a appliqué fixes, ils sont AMENDÉS au commit du ticket (`git commit --amend --no-edit`) — historique propre, 1 ticket = 1 commit final.
- Skip si Phase 2 skipped + Phase 1 skipped (mode `--review-only` sans changement code)

### step-03b-loop-session

- Liste tickets feature triés par priority
- Pour chaque ticket non-fermé:
  - Run step-03a sur ticket → produit 1 commit atomique du ticket
  - Update ticket status (in-progress → done)
  - Continue ou stop sur error (`-a` continue, sinon AskUserQuestion)
- Track itérations vs `-n`
- Push branch en bloc à fin de loop (step-04-sync)

### step-03c-loop-daemon

- Génère `daemon.sh` depuis template `_shared/templates/daemon.sh.tpl`
- Affiche commande `bash .claude/product/features/{id}/daemon.sh -n 20`
- **Ne lance jamais** (setup-only, user contrôle exécution)

#### Template `daemon.sh.tpl`

```bash
#!/usr/bin/env bash
# Generated by /develop --loop=daemon. Edit at will.
# Usage: bash daemon.sh [max_iterations]
set -euo pipefail

MAX="${1:-20}"
FEATURE="{{FEATURE_ID}}"   # injecté par step-03c
LOG_DIR=".claude/product/features/${FEATURE}"
mkdir -p "$LOG_DIR"

for i in $(seq 1 "$MAX"); do
  echo "=== Iteration $i/$MAX ==="

  # Snapshot tree state avant
  BEFORE=$(git rev-parse HEAD 2>/dev/null || echo "init")

  # Invoke skill develop session loop (1 ticket par session)
  claude -p "/develop -a --loop=session ${FEATURE}" \
    >> "${LOG_DIR}/daemon.log" 2>&1 || {
      echo "develop failed iter $i — see daemon.log"
      exit 1
    }

  # Exit conditions
  AFTER=$(git rev-parse HEAD)
  if [ "$BEFORE" = "$AFTER" ]; then
    echo "No commit produced — feature done or blocked. Exiting."
    break
  fi
done

echo "Daemon finished after $i iterations."
```

Variables injectées par step-03c: `{{FEATURE_ID}}`. User edit `MAX` ou ajoute conditions custom (ex: stop si ticket spécifique done).

### step-04-sync

- Push branch (commits atomiques par ticket déjà créés step-03a/b)
- Update ticket plateforme: `tickets-adapter.sh update <id> {status: done}` + `comment <id> "Resolved by {pr_url}"`
- Crée PR/MR via `tickets-adapter.sh` (gh/glab) avec template résolu via
  `_shared/resolve-template.sh --kind=pr --platform=$repository.platform`
  (override `templates.pr` > bundlé `_shared/templates/pr/{platform}.md`).
- Post review-thread (best-effort) — rendu via `templates.review_thread` resolved,
  posté via `tickets-adapter.sh comment-pr` (github/gitlab uniquement;
  jira renvoie not_supported, log warn et continue).
- Pas d'auto-merge configuré côté skill (v1) — user merge PR manuellement après review humaine
- Update `index.md` état: `developed`

### step-05-finish

- Mode standalone:
  - Propose `/qa {ticket-id}` pour validation runtime (régression + wireframes)
  - Sinon propose ticket suivant
- Mode loop: résumé X/Y tickets done. Suggère `/qa {feature-id}` pour run QA batch
