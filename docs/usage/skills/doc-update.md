# `/snap:doc-update` — rafraîchir la doc fonctionnelle vivante

Met à jour les pages parcours impactées par une feature après son ship. Lit le
PRD + le contenu parcours courant + le diff git de la feature, puis patche ou
réécrit les pages parcours via l'IA.

## À quoi ça sert

Garder la doc fonctionnelle **vivante** à jour après livraison.

- La page **PRD** (`Change Requests/{YYYY}/{MM-YYYY}/`) n'est **jamais
  modifiée** — archive immuable de l'intention.
- Les pages **parcours** (`Product Docs/{domain}/{journey}/`) sont la spec
  vivante — ce skill les maintient à jour.

## Quand l'utiliser

| Source                  | Condition                                                                       |
| ----------------------- | ------------------------------------------------------------------------------- |
| Auto post-`/snap:qa`    | `documentation.auto_update_on_qa_success: true` ET la feature passe à `qa-validated`. |
| Manuel                  | `/snap:doc-update --feature=NN-slug`.                                           |

## Prérequis

- `/snap:init` lancé (`snapship.config.json` existe).
- `documentation.platform ∈ {affine, notion}` (ignoré si `none`).
- MCP de cette plateforme joignable.
- La feature a un `manifest.json` avec `state == "qa-validated"` et `prd.page_id`
  renseigné.
- Chaque entrée `impacted_journeys[]` a une entrée correspondante dans
  `_taxonomy.json`.

## Syntaxe

```
/snap:doc-update --feature=NN-slug [--mode=diff|rewrite] [--dry-run] [-a]
```

## Flags

| Flag                  | Effet                                                                            |
| --------------------- | -------------------------------------------------------------------------------- |
| `--feature=NN-slug`   | **Requis.** Partial-match sur `feature_id` (ex. `01` → `01-auth`).               |
| `--mode=diff\|rewrite`| Surcharge `documentation.auto_update_mode`. `diff` = patch IA, `rewrite` = réécriture complète. |
| `--dry-run`           | Rend les mises à jour proposées en local, ne pousse pas vers AFFiNE / Notion.    |
| `-a` / `--auto`       | Ignore les confirmations (utilisé par le hook post-QA).                          |

## Pipeline

| #  | Step                  | Rôle                                                                              |
| -- | --------------------- | --------------------------------------------------------------------------------- |
| 00 | `step-00-init.md`     | Parse args, exige `/snap:init`, valide l'état de la feature, charge PRD + refs parcours. |
| 01 | `step-01-collect.md`  | Récupère le contenu de la page PRD, les pages parcours courantes, le diff git ticket-level de la feature. |
| 02 | `step-02-update.md`   | Par parcours impacté : l'IA génère un patch (`mode=diff`) ou une réécriture complète (`mode=rewrite`). |
| 03 | `step-03-publish.md`  | Pousse les mises à jour via `docs-adapter --action=update-page-content`.          |
| 04 | `step-04-finish.md`   | Télémétrie + entrée progress. Terminal.                                           |

Steps **idempotents** : relancer avec la même feature + le même état git produit
le même diff (modulo non-déterminisme IA — relire avant push).

## Outputs

- Page(s) parcours mises à jour sur AFFiNE / Notion (la page PRD reste intacte).
- Entrée `progress.json` : `doc-update step-04 finish — ok` (ou `dry-run` / `skip`).
- Événement de télémétrie `doc-update`.

## Étape suivante

Terminal — la feature est livrée et sa doc est à jour.
