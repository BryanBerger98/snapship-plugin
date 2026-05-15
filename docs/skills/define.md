# `/snap:define` — définition produit

Construit les PRD (global puis par feature) à partir d'une vision, de personas
et d'une liste de features. Déroule un questionnaire guidé via
`AskUserQuestion` puis publie le résultat sur AFFiNE / Notion.

## À quoi ça sert

Poser ou étendre la définition produit **avant tout ticket**. Le skill
distingue deux chemins :

- **Greenfield** : aucun PRD encore → questionnaire complet (vision → personas
  → features).
- **Extension** : `.snap/` contient déjà des features → ajoute une ou
  plusieurs nouvelles features.

## Quand l'utiliser

- Juste après `/snap:init` sur un nouveau projet.
- Sur un projet existant pour cadrer une nouvelle feature.
- En reprise après interruption (`--resume`).

## Prérequis

`/snap:init` lancé une fois. Le skill sort immédiatement si
`snapship.config.json` est absent.

## Syntaxe

```
/snap:define [--resume|-r] [--lang=fr|en] [--feature=NN-slug]
```

## Flags

| Flag                  | Effet                                                                                                       |
| --------------------- | ----------------------------------------------------------------------------------------------------------- |
| `--resume` / `-r`     | Reprend au dernier step réussi enregistré dans `progress.json`. Partial-match du `feature_id` (`01` → `01-auth`). Sans run en cours, repart au step-00. |
| `--lang=fr\|en`       | Force la langue du PRD (défaut : détectée depuis un PRD existant, sinon demandée).                          |
| `--feature=NN-slug`   | Saute le chemin greenfield, va directement au PRD d'une feature existante.                                  |

## Pipeline

| #  | Step                  | Rôle                                                                       |
| -- | --------------------- | -------------------------------------------------------------------------- |
| 00 | `step-00-init.md`     | Parse les args, exige `snapship.config.json`, détecte le codebase, branche greenfield vs extension. |
| 01 | `step-01-vision.md`   | Questionne la vision + la north star metric.                               |
| 02 | `step-02-personas.md` | Questionne 1 à N personas.                                                 |
| 03 | `step-03-features.md` | Questionne la liste de features avec priorités.                            |
| 04 | `step-04-render.md`   | Génère les PRD par feature (format change-request) depuis les templates.   |
| 05 | `step-05-publish.md`  | Archive les pages PRD par date, garantit l'existence des pages domaine + parcours. |

Steps **idempotents** : relancer un step avec les mêmes entrées produit la même sortie.

## Outputs

- `.snap/manifests/{feature_id}/prd-feature.md` — un par feature.
- `.snap/manifests/{feature_id}.manifest.json` — `state=defined`,
  `domains[]`, `impacted_journeys[]`, `prd.{page_id,url,path}` après publication.
- `.snap/manifests/_taxonomy.json` — IDs des pages domaine + parcours (idempotent).
- `.snap/progress.json` — journal de run.
- AFFiNE / Notion :
  - Page PRD sous `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}` (archive immuable).
  - Pages domaine + parcours sous `{functional_root}/{domain}/{journey}` (spec
    vivante, corps rempli plus tard par `/snap:doc-update`).

## Étape suivante

`/snap:ticket --feature=NN-slug` pour décomposer la feature en tickets.
