# `/snap:ticket` — feature → tickets

Décompose le PRD d'une feature en tickets atomiques prêts pour le dev, enrichit
chacun via des agents de recherche parallèles, les formate selon la plateforme
et les pousse sur GitHub / GitLab / JIRA.

## À quoi ça sert

Transformer un PRD de feature en liste numérotée de stories prêtes pour
`/snap:develop` — chaque ticket fait 5 à 30 min de travail et touche 1 à 5
fichiers.

## Quand l'utiliser

- Un `prd-feature.md` existe dans `.claude/product/features/{feature_id}/`.
- Tu veux des stories dev-ready sur la plateforme de tickets configurée.
- En reprise après interruption (`--resume`).

## Prérequis

`/snap:init` et `/snap:define` lancés. Une plateforme de tickets résolue
(MCP en priorité, sinon CLI `gh` / `glab` / `jira`).

## Syntaxe

```
/snap:ticket [--resume|-r] [--feature=NN-slug] [--platform=github|gitlab|jira]
             [--max-stories=N] [--dry-run]
```

## Flags

| Flag                          | Effet                                                                                  |
| ----------------------------- | -------------------------------------------------------------------------------------- |
| `--resume` / `-r`             | Reprend au dernier step réussi du `progress.md` de la feature (partial-match `feature_id`). |
| `--feature=NN-slug`           | Cible le `feature_id` (requis si plusieurs features définies).                         |
| `--platform=github\|gitlab\|jira` | Force la plateforme, surcharge `config.tickets.platform`.                          |
| `--max-stories=N`             | Plafonne la décomposition automatique (défaut : 12).                                   |
| `--dry-run`                   | Formate et journalise mais n'écrit pas sur la plateforme.                              |

## Pipeline

| #  | Step                   | Rôle                                                              |
| -- | ---------------------- | ----------------------------------------------------------------- |
| 00 | `step-00-init.md`      | Parse les args, résout le `feature_id`, charge le PRD + config.   |
| 01 | `step-01-load.md`      | Lit `prd-feature.md`, extrait les critères d'acceptation + le scope. |
| 02 | `step-02-decompose.md` | Découpe la feature en stories atomiques (5-30 min, 1-5 fichiers). |
| 03 | `step-03-enrich.md`    | Agents parallèles : codebase / docs / recherche web par story.    |
| 04 | `step-04-format.md`    | Rend chaque story via `templates/ticket-{platform}.md`.           |
| 05 | `step-05-push.md`      | Pousse via `tickets-adapter.sh` (MCP > CLI).                      |
| 06 | `step-06-index.md`     | Met en cache `tickets.json` + met à jour le `meta.json` de la feature. |

## Outputs

- `.claude/product/features/{feature_id}/tickets.json` — tableau de tickets en
  cache (id, titre, body, labels, status, platform_url). Validé contre
  `_shared/schemas/tickets.schema.json`.
- `.claude/product/features/{feature_id}/meta.json` — `tickets_count` mis à jour.
- Tickets créés sur GitHub / GitLab / JIRA (URLs cachées ci-dessus).
- `.claude/product/features/{feature_id}/progress.md` — journal de run.

## Étape suivante

`/snap:wireframe` ou `/snap:design` si la feature a de l'UI, sinon directement
`/snap:develop`.
