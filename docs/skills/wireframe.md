# Skill `/wireframe`

Génère wireframes multi-écrans pour une feature via Frame0 ou Penpot MCP. Lie wireframes aux tickets correspondants.

## Frontmatter

```yaml
name: wireframe
description: Génère wireframes Frame0/Penpot multi-écrans pour une feature. Lie wireframes aux tickets correspondants.
argument-hint: "[-a] [-r] [--no-link] [--dry-run] <feature-id>"
```

## Flags

- `-a` autonomous, `-r` resume, `-i` interactive strict
- `--no-link` skip étape link tickets/AFFiNE
- `--dry-run` preview sans write calls

## Plateformes supportées

| Plateforme | Helper                                  | Export                                              |
|------------|-----------------------------------------|-----------------------------------------------------|
| `frame0`   | `skills/_shared/frame0-helper.sh`       | HTTP bypass desktop API + décode base64 local      |
| `penpot`   | `skills/_shared/penpot-helper.sh`       | MCP `export_shape` (filePath absolu, écrit direct) |

Résolu à step-00 via `config.wireframes.platform`. Les deux helpers exposent
la même API d'actions (`create-page`, `add-shapes`, `export-png`, …).

## Frame0 MCP tools utilisés (28 dispo)

- `add_page`, `update_page`, `duplicate_page`
- `create_rectangle`, `create_text`, `create_line`, `create_icon`
- `move_shape`, `align_shapes`, `group_shapes`
- `export_page` (PNG)
- `set_link`

## Penpot MCP tools utilisés (3 + 1 export)

- `execute_code` — JS arbitraire dans le contexte plugin (globals : `penpot`,
  `penpotUtils`, `storage`, `console`). Couvre tous les CRUD pages/shapes :
  `penpot.createPage()`, `createRectangle()`, `createText()`, `createEllipse()`,
  `penpotUtils.getPageById()`, `findShapes()`, `removePage()`.
- `query_docs` — introspection types/membres API (utile pour debug).
- `get_overview` — instructions et hiérarchie File > Pages > Boards > Groups > Shapes.
- `export_shape` — export PNG/SVG (paramètre `filePath` doit être absolu).

## Steps

### step-00-init

Vérifie MCP `frame0-mcp-server` actif. Si absent → erreur claire avec install command. Charge tickets feature.

### step-01-screens

- Filtre tickets UI (heuristique: mots-clés "page", "écran", "form", "modal", "view")
- AskUserQuestion: confirme liste écrans à wireframer
- Pour chaque écran: identifie états (default/loading/error/empty)

### step-02-design (boucle par écran)

- Génère structure: header, content, actions
- Crée page Frame0 via MCP
- Place shapes (composants UI inférés des AC tickets)
- Export PNG → `features/{id}/wireframes/{screen}.png`
- AskUserQuestion: ✓ next / adjust / regenerate
- Si adjust: AskUserQuestion zones à modifier

### step-03-link (sauf `--no-link`)

- Update `manifest.json`: mapping screen ↔ ticket-id ↔ frame0_page_id
- **Crée page AFFiNE "Wireframes Gallery"** sous PRD feature:
  - Duplique template `templates.wireframes_gallery` si défini
  - Embed/upload screenshots PNG via MCP (blob storage)
  - Pour chaque écran: titre + image + lien ticket plateforme + lien Frame0 page
  - Sauvegarde page_id dans `meta.json`: `{ "affine_wireframes_page_id": "..." }`
- Update tickets plateforme: ajoute lien AFFiNE gallery + lien wireframe spécifique
- Update `index.md` état: `wireframed`

### step-04-finish

Propose `/develop {feature-id}`.
