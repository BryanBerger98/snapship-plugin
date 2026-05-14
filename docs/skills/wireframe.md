# `/snap:wireframe` — tickets UI → wireframes low-fi

Génère des wireframes low-fi pour les tickets UI d'une feature via la plateforme
de wireframe configurée (Frame0, Penpot ou Figma), construit une page Gallery
dans la doc, et back-link les URLs de wireframe dans les tickets.

## À quoi ça sert

Passer une feature en wireframes basse fidélité **avant `/snap:develop`**,
quand des tickets touchent l'UI.

## Quand l'utiliser

- Une feature a un `tickets.json` avec au moins un ticket touchant des fichiers
  UI (heuristique mots-clés + extensions, step-01).
- Une plateforme de wireframe est configurée :
  `config.wireframes.platform ∈ {frame0, penpot, figma}`.
- `/snap:define` a rempli `prd-feature.md` (noms d'écrans + états connus).

## Plateformes supportées

| `wireframes.platform` | Helper                            | Surface                                      |
| --------------------- | --------------------------------- | -------------------------------------------- |
| `frame0`              | `_shared/frame0-helper.sh`        | App Desktop + MCP                            |
| `penpot`              | `_shared/penpot-helper.sh`        | App web + plugin MCP                         |
| `figma`               | `_shared/figma-helper.sh`         | Figma Desktop + `figma-console-mcp` + plugin Bridge |
| `none` (absent)       | —                                 | Skill ignoré                                 |

Le skill est platform-agnostic au niveau orchestration : step-00 résout
`config.wireframes.platform` → un helper, et chaque step suivant l'appelle via
la variable `$helper`.

> **Figma** : nécessite Figma Desktop lancé, le plugin Desktop Bridge actif, et
> un token dans `.env.snapship` (clé `FIGMA_ACCESS_TOKEN`, override
> `wireframes.figma.token_env`). step-00 halt si `figma.fileKey` ne correspond
> pas à `wireframes.figma.file_key`.

## Syntaxe

```
/snap:wireframe [--resume|-r] [--feature=NN-slug] [--dry-run]
```

## Flags

| Flag                | Effet                                                                            |
| ------------------- | -------------------------------------------------------------------------------- |
| `--resume` / `-r`   | Reprend via `resume-state.sh next --skill=wireframe`.                            |
| `--feature=NN-slug` | Cible le `feature_id` (requis si plusieurs features ; partial-match).            |
| `--dry-run`         | Les helpers retournent des descripteurs mock : aucun appel MCP, aucun PNG ni écriture doc. |

## Pipeline

| #  | Step                 | Rôle                                                                       |
| -- | -------------------- | -------------------------------------------------------------------------- |
| 00 | `step-00-init.md`    | Parse les args, résout feature + plateforme + helper, préflight plateforme.|
| 01 | `step-01-filter.md`  | Identifie les tickets UI via heuristique mots-clés + extensions.           |
| 02 | `step-02-design.md`  | Par écran : crée la page, ajoute les shapes, exporte le PNG via le helper. |
| 03 | `step-03-gallery.md` | Page Gallery dans la doc : upload des PNG, embed par écran + état.         |
| 04 | `step-04-link.md`    | Met à jour chaque ticket UI avec `wireframe_url` + `wireframe_screen`.     |

## Outputs

- `.claude/product/features/{feature_id}/wireframes/{screen-id}-{state}.png`
  (cache local).
- Page Gallery dans la doc (URL cachée dans `.docs-cache.json` sous
  `wireframes_gallery.url`).
- `.claude/product/wireframes-gallery.md` — une section par écran.
- Chaque ticket UI dans `tickets.json` gagne `wireframe_screen` + `wireframe_url`.

## Étape suivante

`/snap:design` pour des maquettes haute fidélité, ou `/snap:develop`.
