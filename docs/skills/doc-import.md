# `/snap:doc-import` — import des docs legacy dans la structure SnapShip

Importe des pages de doc free-form (AFFiNE / Notion) dans la hiérarchie SnapShip
v0.2 (`functional_root` → domaine → parcours utilisateur). One-shot par projet ;
produit `domains.json`.

## À quoi ça sert

Onboarder un codebase qui a déjà des pages de doc dispersées. Produit une
hiérarchie `Product Docs/` peuplée + `domains.json`, pour que les
`/snap:define` suivants puissent retrouver-ou-créer les pages parcours par slug.

> Ce n'est **pas un outil de migration** : SnapShip v0.1 → v0.2 n'a pas de
> migration (pilote uniquement).

## Quand l'utiliser

- Projet existant avec des pages de doc legacy éparpillées, trop nombreuses pour
  être réorganisées à la main avant le premier `/snap:define`.
- Bootstrap **one-shot**. Les re-runs exigent `--force` (typiquement après un
  dry-run raté ou pour refaire l'analyse avec un autre source root).

## Prérequis

- `/snap:init` lancé (`snapship.config.json` + `.claude/product/` existent).
- `documentation.platform ∈ {affine, notion}` (ignoré si `none`).
- Serveur MCP de cette plateforme joignable dans la session courante.
- `domains.json` vide **ou** `--force` (refuse d'écraser un import existant).

## Syntaxe

```
/snap:doc-import
  --source-page=<page-id-or-url>     # racine AFFiNE à scanner (omis = racine workspace)
  --strategy=synthesize|copy|move    # défaut : synthesize
  [--dry-run]                        # prévisualise le mapping ; aucune écriture
  [--backup]                         # exporte les pages source vers .claude/product/.backup/
  [-a|--auto]                        # autonome (ignore les confirmations ; proposition IA telle quelle)
  [--force]                          # bypass le garde domains.json non-vide
```

## Flags

| Flag                     | Effet                                                                          |
| ------------------------ | ------------------------------------------------------------------------------ |
| `--source-page=<id\|url>`| Racine AFFiNE à scanner. Omis → racine du workspace.                           |
| `--strategy=...`         | Stratégie d'import (voir ci-dessous). Défaut : `synthesize`.                    |
| `--dry-run`              | Prévisualise le mapping page → cible, aucune écriture AFFiNE.                   |
| `--backup`               | Exporte les pages source vers `.claude/product/.backup/`.                      |
| `-a` / `--auto`          | Autonome : ignore les confirmations, utilise la proposition IA telle quelle.   |
| `--force`                | Bypass le garde « `domains.json` non-vide ».                                   |

## Stratégies

| Stratégie                | Mécanique                                                                                       | À utiliser quand                          |
| ------------------------ | ----------------------------------------------------------------------------------------------- | ----------------------------------------- |
| **synthesize** (défaut)  | L'IA consolide N pages source → 1 doc parcours. Les pages source sont taguées `[snap-imported]`. | La doc legacy est désordonnée / éparpillée. |
| **copy**                 | Duplique le contenu source vers de nouvelles pages sous le chemin SnapShip. Les originales vont dans `Archive/imported-{date}/`. | Préserver le contenu verbatim.            |
| **move**                 | Renomme + reparente les pages source vers le chemin SnapShip. Préserve l'historique AFFiNE.     | La doc est déjà bien structurée, juste au mauvais chemin. |

## Pipeline

| #  | Step                     | Rôle                                                                          |
| -- | ------------------------ | ----------------------------------------------------------------------------- |
| 00 | `step-00-init.md`        | Parse args, exige `/snap:init`, valide plateforme + MCP, garde `domains.json` non-vide. |
| 01 | `step-01-crawl.md`       | Liste les pages source (sous-arbre `--source-page` ou racine workspace), construit l'index. |
| 02 | `step-02-analyze.md`     | L'IA propose domaines + parcours + mapping page → cible ; émet `proposed_structure` JSON. |
| 03 | `step-03-confirm.md`     | Revue via `AskUserQuestion` ; édition JSON possible avant commit.              |
| 04 | `step-04-restructure.md` | Exécute la stratégie (synthesize / copy / move) ; écrit les pages via docs-adapter. |
| 05 | `step-05-finish.md`      | Persiste `domains.json`, télémétrie, entrée progress.                         |

Steps **idempotents re-entrants sur fail partiel** : les pages déjà migrées
portent le tag `[snap-imported]` et sont sautées au re-run.

## Outputs

- Pages `Product Docs/{domain}/{journey}` peuplées sur AFFiNE / Notion.
- `.claude/product/domains.json` rempli (IDs des pages domaine + parcours).
- `.claude/product/.backup/` (si `--backup`).
- Entrée `progress.md` + événement de télémétrie `doc-import`.
- **Non produit** : `Change Requests/*` (les PRD viennent via `/snap:define`),
  features `meta.json` (aucun `feature_id` n'existe encore).

## Étape suivante

`/snap:define` pour cadrer la première feature dans la structure importée.
