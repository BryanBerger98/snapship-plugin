# `/snap:develop` — ticket → code committé

Implémente des tickets : analyse l'impact, écrit le code, lance trois reviewers
en parallèle (technique + fonctionnel + sécurité), applique le feedback agrégé,
puis produit des commits atomiques et pousse la branche.

## À quoi ça sert

Prendre un ticket (mode standalone) ou itérer sur les tickets d'une feature
(mode loop session / daemon), les implémenter, faire converger les reviewers,
et livrer un commit atomique par ticket.

## Quand l'utiliser

- Une feature a un `tickets.json` avec au moins un ticket `todo` /
  `in_progress`.
- Le working tree est propre (ou `--allow-dirty`).
- Le repo est un dépôt git sur une branche committable (pas directement sur une
  branche protégée — la branche est créée idempotemment par ticket / feature).

## Syntaxe

```
/snap:develop                              # AskUserQuestion → choisir ticket ou feature
/snap:develop <ticket-id>                  # standalone (ex. AUTH-12, #42, t-001)
/snap:develop <feature-id>                 # loop — demande --loop=session|daemon
/snap:develop <feature-id> --loop=session  # itère dans la même session Claude
/snap:develop <feature-id> --loop=daemon   # génère daemon.sh (lancement manuel)
/snap:develop --resume | -r
/snap:develop --dry-run
/snap:develop --allow-dirty
/snap:develop --retry-fallback=next-ticket|stop
```

## Flags

| Flag                                       | Effet                                                                                  |
| ------------------------------------------ | -------------------------------------------------------------------------------------- |
| `<ticket-id>`                              | Mode standalone : un seul ticket.                                                      |
| `<feature-id>`                             | Mode loop : itère sur les tickets de la feature (demande le mode si non précisé).      |
| `--loop=session`                           | Itère sur les tickets dans la même session Claude.                                     |
| `--loop=daemon`                            | Génère `daemon.sh` (jamais lancé automatiquement — l'utilisateur fait `bash daemon.sh -n N`). |
| `--resume` / `-r`                          | Reprend via `resume-state.sh next --skill=develop`.                                    |
| `--dry-run`                                | Aucune écriture : pas de commit ni de push, les reviewers tournent sur le diff stagé.  |
| `--allow-dirty`                            | Tolère des changements non committés avant le run.                                     |
| `--retry-fallback=next-ticket\|stop`       | Comportement de repli, uniquement avec `fail_strategy=retry`.                          |

## Pipeline

| #   | Step                       | Rôle                                                                                  |
| --- | -------------------------- | ------------------------------------------------------------------------------------- |
| 00  | `step-00-init.md`          | Parse args, résout la cible (ticket-id ou feature-id), charge la config, pré-flight.  |
| 01  | `step-01-fetch.md`         | Hydrate le(s) ticket(s) depuis le cache → fallback fetch plateforme.                  |
| 02  | `step-02-prepare.md`       | Branche idempotente, chargement des conventions (CLAUDE.md, CONTRIBUTING.md), impact radius. |
| 03a | `step-03a-standalone.md`   | Un ticket : Phase 1 (analyze / plan / execute / validate) + Phase 2 (3 reviewers en parallèle + boucle de fix dev). |
| 03b | `step-03b-loop-session.md` | Plusieurs tickets, même session : foreach ticket → step-03a → commit atomique.        |
| 03c | `step-03c-loop-daemon.md`  | Génère `daemon.sh` (sans lancement auto) — l'utilisateur exécute `bash daemon.sh -n N`. |
| 04  | `step-04-sync.md`          | Push la branche, ouvre la PR (ou met à jour l'existante) via le template résolu (override config > PR template `.github`/`.gitlab` > bundlé), patche `platform_url` + status du ticket. |
| 05  | `step-05-finish.md`        | Met à jour `tickets.json`, propose `/snap:qa`, télémétrie, terminal.                  |

## Configuration (`config.develop`)

```json
{
  "develop": {
    "review_cycles_max": 3,
    "auto_apply_review_feedback": true,
    "fail_strategy": "next-ticket",
    "reviews": {
      "technical": {"severity_threshold": "minor"},
      "functional": {"severity_threshold": "minor"},
      "security":   {"severity_threshold": "major"}
    }
  }
}
```

- `review_cycles_max` — nombre de cycles dev ↔ reviewer en Phase 2 avant échec
  (arrêt anticipé sur `critical`).
- `auto_apply_review_feedback` — si `false`, le feedback est présenté pour
  revue humaine au lieu de relancer l'agent dev.
- `fail_strategy` — comportement quand les cycles sont épuisés :
  - `next-ticket` — log les severities, saute ce ticket, continue (modes loop uniquement).
  - `stop` — dump le `aggregated_feedback`, arrête le run.
  - `retry` — relance la Phase 1 une fois avec `retry_strategy_hint`, puis retombe
    sur `--retry-fallback`.
- `reviews.{type}.severity_threshold` — un finding à ce niveau ou au-dessus
  bloque la fin du cycle. Échelle : `info` < `minor` < `major` < `critical`.

## Outputs

- Un commit git par ticket (`{type}({scope}): {title} ({local_id})`), amendé sur
  les itérations de fix.
- Branche poussée ; PR ouverte (idempotent — un re-run met à jour le body, ne
  duplique pas).
- `tickets.json` mis à jour : `commit_sha`, `developed_at`, `status="in_review"`.
- Entrées de step dans `progress.md` pour chaque ticket.

## Étape suivante

`/snap:qa <ticket-id>` (standalone) ou `/snap:qa <feature-id>` (loop) pour la
validation runtime.
