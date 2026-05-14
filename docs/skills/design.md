# `/snap:design` — maquettes hi-fi

Génère des maquettes haute fidélité pour ce qu'un ticket demande, via la
plateforme de design configurée (Penpot ou Figma). Construit une page
`design-gallery` dans la doc et back-link les URLs dans les tickets.
**Optionnel** — parallèle ou séquentiel à `/snap:wireframe`.

`/snap:design` fait **une seule chose** : des maquettes. Il ne crée ni ne
modifie jamais le design system. Si un fichier DS est configuré, il peut être
**lu** en référence de composants (opt-in via `mode_defaults.design_system_source`)
— le DS est géré hors de ce skill.

## Input

Comme `/snap:develop` et `/snap:qa` :

| Input          | Effet                                          |
| -------------- | ---------------------------------------------- |
| `<ticket-id>`  | Maquette le ticket unique.                     |
| `<feature-id>` | Maquette tous les tickets UI de la feature (batch). |

Partial-match sur l'id. Sans argument (et sans `--resume`), step-00 propose via
`AskUserQuestion` les tickets UI sans `design_url`.

## Quand l'utiliser

- Une feature a un `tickets.json` avec au moins un ticket UI.
- Une plateforme de design est configurée :
  `config.design.platform ∈ {penpot, figma}`.

## Plateformes supportées

| `design.platform` | Helper                       | Surface                                                            |
| ----------------- | ---------------------------- | ------------------------------------------------------------------ |
| `penpot`          | `_shared/penpot-helper.sh`   | Même MCP que `/snap:wireframe penpot` — le skill applique les shapes hi-fi. |
| `figma`           | `_shared/figma-helper.sh`    | Même helper et même plugin Desktop Bridge que `/snap:wireframe figma` (`figma-console-mcp`). |
| `none` (absent)   | —                            | Skill ignoré.                                                      |

`frame0` est **exclu** par conception : Frame0 est low-fi uniquement.
`/snap:design figma` utilise exactement le même helper et le même plugin
Desktop Bridge que `/snap:wireframe figma`.

> **Figma** : nécessite Figma Desktop lancé, le plugin Desktop Bridge actif, et
> un token dans `.env.snapship` (clé `FIGMA_ACCESS_TOKEN`, override
> `design.figma.token_env`).

## Syntaxe

```
/snap:design <ticket-id|feature-id> [--resume|-r] [--dry-run] [--no-wireframe-reuse]
```

## Flags

| Flag                   | Effet                                                                                  |
| ---------------------- | -------------------------------------------------------------------------------------- |
| `<ticket-id\|feature-id>` | Requis sauf avec `--resume`. Ticket id → un ticket ; feature id → tous les tickets UI. |
| `--resume` / `-r`      | Reprend via `resume-state.sh next --skill=design`.                                     |
| `--dry-run`            | Les helpers retournent des descripteurs mock : aucun appel MCP, aucun asset ni écriture doc. |
| `--no-wireframe-reuse` | Saute le prompt « réutiliser les écrans `/wireframe` » ; reconstruit la liste depuis les tickets. |

## Pipeline

| #  | Step                        | Rôle                                                                                 |
| -- | --------------------------- | ------------------------------------------------------------------------------------ |
| 00 | `step-00-init.md`           | Parse les args, résout le scope ticket/feature, charge `config.design`, préflight plateforme, auto-link le binding wireframes si les plateformes correspondent. |
| 01 | `step-01-source-resolve.md` | Construit la liste écran × état depuis le(s) ticket(s) cible(s) ; détecte les wireframes réutilisables. |
| 02 | `step-02-mockup.md`         | Par écran × état : frame, applique shapes/composants, exporte l'asset.                |
| 03 | `step-03-gallery.md`        | Page `design-gallery` dans la doc (séparée de `wireframes-gallery`).                  |
| 04 | `step-04-link.md`           | Chaque ticket cible gagne `design_url` + `design_screen` + `design_mode`.             |

## Auto-link vers `/snap:wireframe`

Si `wireframes.platform == design.platform` **et** un binding wireframes existe
**et** `design.{platform}.{file_id|file_key}` est null → `step-00` pose une
`AskUserQuestion` :

- **Oui, réutiliser le fichier wireframes** → copie le binding vers `design.{platform}`.
- **Non, fichier séparé** → demande le binding `design.{platform}`.
- **Sauvegarder en config** → persiste le choix pour les runs futurs.

## Lecture DS optionnelle

`mode_defaults.design_system_source` pilote la référence de composants en step-02 :

| Valeur  | Effet                                                              |
| ------- | ------------------------------------------------------------------ |
| `none`  | Aucune lecture DS — maquettes from scratch.                        |
| `file`  | Lit le fichier DS configuré (`design.{platform}.design_system_page`) en référence visuelle. |
| `auto`  | Lit le DS s'il est configuré, sinon `none`.                        |

Le DS est **lu uniquement** — `/snap:design` n'y écrit jamais.

## Outputs

- `.claude/product/features/{feature_id}/design/{screen-id}-{state}.{fmt}` (cache local).
- Page `design-gallery` dans la doc (URL cachée dans `.docs-cache.json` sous
  `design_gallery.{feature_id}`).
- `.claude/product/design-gallery.md` — une section par écran.
- Chaque ticket UI cible dans `tickets.json` gagne `design_screen`, `design_url`,
  `design_mode` (`mockup` | `reused`).

## Étape suivante

`/snap:develop` — son step-00 affiche un banner designer-handoff si
`tickets[].design_url` est présent.
