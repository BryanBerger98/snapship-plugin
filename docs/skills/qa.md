# `/snap:qa` — validation runtime des tickets développés

Valide les tickets développés : régression (scope = impacted via
code-review-graph), diff wireframe (Playwright vs Frame0), spawn d'un agent
`code-reviewer-qa`, boucle de fix dev via amend, et retrigger optionnel des
reviewers de `/snap:develop`.

## À quoi ça sert

Valider, après `/snap:develop`, un ou plusieurs commits contre les critères
d'acceptation, la régression, la conformité wireframe et les dérives
sécurité / fonctionnelles introduites après la phase de dev.

## Quand l'utiliser

- Un ticket a un `commit_sha` et `status="in_review"` dans `tickets.json`.
- Le repo a un `test_command` résolu (ou détectable via
  `detect-test-commands.sh`).
- Optionnel : des wireframes Frame0 existent pour les tickets UI → active le
  diff wireframe.

## Différence avec la review fonctionnelle de `/snap:develop`

- Review fonctionnelle = **statique** (lit le code / diff, vérifie les AC
  textuellement).
- QA = **runtime** (exécute les tests, lance l'app, compare le comportement aux
  AC + wireframes).

## Syntaxe

```
/snap:qa                            # AskUserQuestion : quel ticket / feature ?
/snap:qa <ticket-id>                # valide un ticket
/snap:qa <feature-id>               # valide tous les tickets in_review de la feature
/snap:qa --resume | -r
/snap:qa --dry-run
/snap:qa --no-wireframe-check
/snap:qa --retrigger
```

## Flags

| Flag                    | Effet                                                                                |
| ----------------------- | ------------------------------------------------------------------------------------ |
| `<ticket-id>`           | Valide un seul ticket.                                                               |
| `<feature-id>`          | Valide chaque ticket `in_review` de la feature.                                      |
| `--resume` / `-r`       | Reprend via `resume-state.sh next --skill=qa`.                                       |
| `--dry-run`             | Collecte uniquement : pas de boucle de fix, pas d'amend.                             |
| `--no-wireframe-check`  | Saute le diff wireframe même si la config l'active.                                  |
| `--retrigger`           | Force le step-04 même si `config.qa.retrigger_review=false`.                         |

## Pipeline

| #  | Step                    | Rôle                                                                              |
| -- | ----------------------- | --------------------------------------------------------------------------------- |
| 00 | `step-00-init.md`       | Parse args, résout le(s) ticket(s) cible, charge la config, scope le diff.        |
| 01 | `step-01-collect.md`    | Lance la régression (scope impacted / full / tests-only) + diff wireframe Playwright. |
| 02 | `step-02-interpret.md`  | Spawn l'agent `code-reviewer-qa` → severity + `qa_feedback_md`, détection des flaky. |
| 03 | `step-03-fix.md`        | Cycle : l'agent dev applique `qa_feedback` → amend du commit → re-run step-01.     |
| 04 | `step-04-retrigger.md`  | Opt-in : re-run des 3 reviewers de `/snap:develop` sur le diff post-QA (1 retrigger max). |
| 05 | `step-05-finish.md`     | Statut du ticket → `qa-validated` (ou `blocked`), télémétrie, terminal.            |

## Configuration (`config.qa`)

```json
{
  "qa": {
    "qa_cycles_max": 2,
    "auto_apply_qa_feedback": true,
    "severity_threshold": "minor",
    "retrigger_review": false,
    "regression": {"enabled": true, "scope": "impacted"},
    "wireframe_check": {"enabled": false, "mode": "playwright", "diff_threshold_pct": 5}
  }
}
```

- `qa_cycles_max` — cycles de fix dev ↔ QA avant échec.
- `auto_apply_qa_feedback` — si `false`, les findings sont présentés à
  l'utilisateur au lieu de relancer l'agent dev.
- `severity_threshold` — un finding à ce niveau ou au-dessus empêche le ticket
  d'atteindre `qa-validated`.
- `regression.scope` :
  - `impacted` (défaut) — seulement les tests transitivement atteignables depuis
    le diff via `get_affected_flows` (code-review-graph).
  - `full` — lance toute la suite `testing.test_command`.
  - `tests-only` — fallback quand le graphe est indisponible : seulement les
    fichiers `*.test.*` / `*.spec.*` transitivement importés depuis les fichiers
    modifiés.
- `wireframe_check.diff_threshold_pct` — tolérance de diff structurel face aux
  PNG Frame0 ; au-delà → finding.

## Outputs

- Chaque ticket validé : `status="qa-validated"`, `qa_validated_at` renseigné.
- Body du ticket plateforme amendé avec le verdict QA (template par plateforme).
- Entrées de step dans `progress.md`.
- Optionnel : résumé de re-review ajouté (si le retrigger a tourné).

## Étape suivante

`/snap:doc-update --feature=NN-slug` pour rafraîchir la doc fonctionnelle
vivante (auto-déclenché si `documentation.auto_update_on_qa_success: true`).
