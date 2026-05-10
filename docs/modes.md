# Modes & flags

## Mode `-a` (autonomous) — wrapper `ask-or-default.sh`

Tool natif `AskUserQuestion` n'a pas de support documenté pour bypass auto en mode headless. Solution: wrapper helper qui shortcircuit AVANT l'appel tool.

**Pattern:** au lieu d'appeler `AskUserQuestion` directement, skill appelle `_shared/ask-or-default.sh`:

```bash
ask-or-default.sh \
  --auto-mode={auto_mode} \
  --question-id="confirm-platform" \
  --default="github" \
  --question="Quelle plateforme tickets ?" \
  --options="github,gitlab,jira"
```

Comportement:

- Si `--auto-mode=true` → output `{default}` sur stdout, exit 0 (skip prompt)
- Si `--auto-mode=false` → délègue à `AskUserQuestion` (skill orchestre tool call)
- Si `--auto-mode=true` ET `--default` absent → fail explicite (`auto-mode without default: question-id={id}`)

**Bénéfice:** séparation claire défaut machine-readable vs label UI. Pas de parsing fragile sur "(Recommended)".

**Skill responsabilité:** définir un `default` explicite par question pour supporter `-a`. Si une question est genuinely ambiguë sans default sain → ne pas la passer en autonome (fail-fast oriente user).

## Monitoring usage & coût

**Mode economy** (`defaults.economy_mode=true` ou flag `-e`) — réduit parallélisme + cycles:

- **Parallélisme:** `ai.max_parallel_agents` forcé à `1` (override config)
- **Review cycle:** `develop.review_cycles_max` forcé à `1`
- **QA cycle:** `qa.qa_cycles_max` forcé à `1`
- Reste config inchangée (testing, naming, lifecycle_scripts)

Note: economy ne swap PAS le modèle (CC ne supporte pas swap runtime cross-subagents — `model:` figé en frontmatter). Pour réduire coût modèle global: user fait `/model haiku` ou `/effort low`.

Override CLI `--economy=false` désactive même si config `true`.

**Commandes CC natives recommandées (monitoring):**

| Commande   | Usage                                                             |
| ---------- | ----------------------------------------------------------------- |
| `/usage`   | Tokens consommés session courante + breakdown par model/tool      |
| `/cost`    | Estimation coût $ session                                          |
| `rtk gain` | Si RTK installé — savings tokens via proxy CLI                    |

Step-finish chaque skill suggère: "Check `/usage` ou `/cost` post-run pour tracker conso. Iter sur `develop.review_cycles_max` ou `--economy` si trop coûteux."

**Telemetry locale `_shared/telemetry.log`** (NDJSON append-only):

Chaque step-XX appel `telemetry.sh` start + end:

```
{"ts":"2026-05-09T10:00:00Z","skill":"develop","step":"step-03a:execute","duration_ms":12340,"status":"ok","ticket_id":"PROJ-12","cycle":1}
```

Champs: `ts | skill | step | duration_ms | status | ticket_id? | cycle? | severity?`. Pas de PII. Rotation automatique > 10MB (renomme `.1`, garde 2 fichiers max). Gitignored. Sert itération plan v2 (identifier steps lents, cycles fréquents, retries).

## Resume mode — pattern unifié

Chaque skill, step-00:

```
Si {resume_id} set:
  1. ls .claude/product/features/ | grep ^{resume_id}
  2. Si match: read meta.json, tickets.json, wireframes/manifest.json, progress.md
  3. (Optionnel) fetch PRD docs via meta.json.affine_page_id si contexte produit requis
  4. Détermine dernière étape complétée (parse progress.md)
  5. Load step suivant
  6. Sinon: liste features dispo, AskUserQuestion
```

## Format strict `progress.md`

Fichier append-only par feature. Chaque ligne = 1 event horodaté. Parser regex line-based, pas markdown sémantique.

**Header (créé au premier `/define` de la feature):**

```markdown
# Progress — {feature_id}

started: {ISO-8601 UTC}
```

**Events (1 ligne = 1 event):**

```
{ISO-8601 UTC} | {skill} | {step} | {status} | {key=value;key=value} | {note}
```

| Champ        | Format                                               | Exemple                          |
| ------------ | ---------------------------------------------------- | -------------------------------- |
| timestamp    | `YYYY-MM-DDTHH:MM:SSZ`                               | `2026-05-09T14:32:11Z`           |
| skill        | `define\|ticket\|wireframe\|develop\|qa`             | `develop`                        |
| step         | step-id (`step-XX-name` ou sub-step `analyze`/`plan`)| `step-03a-standalone:execute`    |
| status       | `start\|ok\|fail\|skip\|retry`                       | `ok`                             |
| metadata     | `key=value;key=value` (URL-encoded, vide = `-`)      | `ticket=PROJ-12;cycle=2`         |
| note         | freetext (1 ligne, no pipe — escape `\|`)            | `severity=minor; AC 3/4 cochés`  |

**Exemple complet:**

```
# Progress — 01-auth

started: 2026-05-09T10:00:00Z

2026-05-09T10:00:05Z | define | step-02-vision | ok | - | vision validée user
2026-05-09T10:15:22Z | ticket | step-03-format | ok | count=4 | 4 tickets draft
2026-05-09T11:02:14Z | develop | step-03a-standalone:analyze | start | ticket=PROJ-12 | -
2026-05-09T11:08:33Z | develop | step-03a-standalone:execute | ok | ticket=PROJ-12 | files=3
2026-05-09T11:09:01Z | develop | step-03a-standalone:review | retry | ticket=PROJ-12;cycle=1 | sec=major
2026-05-09T11:14:50Z | develop | step-03a-standalone:review | ok | ticket=PROJ-12;cycle=2 | all<minor
2026-05-09T11:32:00Z | qa | step-01-collect | fail | ticket=PROJ-12 | regression: 1 fail (login_test)
```

**Règles parser:**

- Resume cherche dernier event status `ok` ou `skip` → reprend step suivant
- `retry` n'avance pas le pointeur, indique itération
- `fail` non suivi de `retry`/`ok` → state bloqué, resume re-prompt user
- Flaky detection (`/qa`): groupe events par `(skill, step, ticket)` sur fenêtre 7 jours, count `fail` → `ok` sans code change entre = flaky candidate (voir Flaky detection)

## Flaky detection heuristique (`/qa` step-02-interpret)

Subagent `code-reviewer-qa` reçoit raw output + extrait `progress.md` (events `qa` même feature/ticket fenêtre 7 jours). Logique:

```
flaky_score = 0
events = filter(progress, skill=qa, ticket={current}, last_7d)
groups = groupby(events, (step, test_name))

pour chaque group:
  fails = count(status=fail)
  oks   = count(status=ok)
  si fails ≥ 1 ET oks ≥ 1 ET aucun commit entre fail→ok du même test:
    flaky_score += 1
    ajoute test_name → flaky_list
```

**Heuristique commit-between:** check `git log --oneline {ts_fail}..{ts_ok}` sur fichiers test + impl (via `code-review-graph` `tests_for`). 0 commit modifiant ces fichiers → flaky probable.

**Output subagent:**

```json
{
  "severity": "minor",
  "feedback_md": "...",
  "flaky_candidates": ["login_test", "checkout_e2e"],
  "stable_failures": ["payment_validate_test"]
}
```

`flaky_candidates` → severity downgraded `major→minor`, `feedback_md` recommande quarantine + investigate.
`stable_failures` → severity preserved, fix obligatoire avant exit cycle.

## `--dry-run` global (preview sans write calls)

Tous skills acceptent `--dry-run`:

- Adapters (`tickets-adapter.sh`, `docs-adapter.sh`, `frame0-helper.sh`) check `{dry_run}` env var:
  - Read ops (fetch tickets, list pages) → exécutées normalement (read-only safe)
  - Write ops (create ticket, push page, comment, update status, push commits, create PR) → log stdout `[DRY-RUN] would: <action> <args>`, skip exec
- Git ops: `git commit` skip, `git push` skip — log diff qui aurait été commité
- AskUserQuestion → exécuté normalement (user input pas un side-effect prod)
- Telemetry → log avec `"dry_run": true` flag
- step-finish affiche récap: "Dry-run terminé. N actions skipped: [...]. Re-run sans --dry-run pour appliquer."

Combinable avec `-a` autonomous: skill court de bout en bout avec defaults, expose plan complet sans toucher prod.

## SessionStart hook opt-in (pre-load config)

Optionnel pour user qui travaille fréquemment dans projet snap.

**Setup:** copier template plugin vers location user, puis ajouter dans `~/.claude/settings.json` ou `.claude/settings.json` projet:

```bash
# 1. Copier template (renommé sans .tpl) vers location user-contrôlée
cp ~/.claude/skills/_shared/templates/session-start-hook.sh.tpl \
   ~/.claude/lifecycle_scripts/session-start-hook.sh
chmod +x ~/.claude/lifecycle_scripts/session-start-hook.sh
```

```json
{
  "hooks": {
    "SessionStart": [{
      "type": "command",
      "command": "bash ~/.claude/lifecycle_scripts/session-start-hook.sh"
    }]
  }
}
```

> Le `.tpl` reste read-only dans le plugin (mis à jour par updates plugin). User édite la copie sans risque écrasement.

**Template `session-start-hook.sh.tpl`:**

```bash
#!/usr/bin/env bash
# Pre-load snap context si projet courant a config
CONFIG=".claude/product/snapship.config.json"
[ -f "$CONFIG" ] || exit 0

# Output additionalContext via JSON sortie (format CC SessionStart)
RESOLVED=$(bash ~/.claude/skills/_shared/load-config.sh 2>/dev/null) || exit 0
PLATFORM=$(echo "$RESOLVED" | jq -r '.tickets.platform')
DOCS=$(echo "$RESOLVED" | jq -r '.documentation.platform')

cat <<EOF
{
  "additionalContext": "snap active. Tickets: $PLATFORM. Docs: $DOCS. Skills: /define /ticket /wireframe /develop /qa."
}
EOF
```

**Bénéfice:** skills accèdent contexte sans re-parse à chaque step-00 (cache `.config-resolved.json` reste source vérité runtime). User contrôle activation — pas de patch automatique settings.json.
