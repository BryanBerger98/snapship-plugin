# Skill `/wireframe`

Génère wireframes multi-écrans pour une feature via Frame0, Penpot ou Figma MCP. Lie wireframes aux tickets correspondants.

## Frontmatter

```yaml
name: wireframe
description: Génère wireframes Frame0/Penpot/Figma multi-écrans pour une feature. Lie wireframes aux tickets correspondants.
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
| `figma`    | `skills/_shared/figma-helper.sh`        | `figma_execute` retourne base64 inline → `save-export` décode local |

Résolu à step-00 via `config.wireframes.platform`. Les trois helpers exposent
la même API d'actions (`create-page`, `add-shapes`, `export-png`, …).

Helpers context-agnostic depuis v0.5 : aucune lecture de config — step-00
résout les valeurs nichées (`api_port`, `penpot.file_id`, `figma.file_key`,
`export_format`, …) et les passe explicitement à chaque appel.

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

## Figma MCP tools utilisés (`figma-console-mcp`, ~100 dispo)

Une seule MCP utilisée comme primitive universelle :

- `figma_execute` — exécute du JS dans le contexte Figma Plugin API via la
  Desktop Bridge plugin (WebSocket auto-discovery ports 9223–9232). Couvre :
  - `figma.createPage()`, `figma.currentPage = page` — gestion pages
  - `figma.createRectangle()`, `createText()`, `createEllipse()`,
    `createFrame()` — shapes
  - `figma.loadFontAsync({family:"Inter", style:"Regular"})` requis avant
    tout texte
  - `node.exportAsync({format, constraint:{type:"SCALE", value}})` →
    `Uint8Array` → `figma.base64Encode(bytes)` retourné inline dans la
    réponse MCP
  - `figma.getNodeById(id)`, `figma.root.findAll()` — lookup
- Couleurs : Figma utilise `{r,g,b}` 0–1 (pas 0–255). Le helper convertit
  `#hex` → RGB en JS.

### Prérequis Figma

1. **Figma Desktop** lancé (pas le navigateur — la Bridge n'existe que sur
   Desktop).
2. **Desktop Bridge plugin** installé et actif : Figma → Plugins → Browse →
   "Desktop Bridge" → Open. La plugin maintient le WebSocket que
   `figma-console-mcp` interroge.
3. **Token Figma** dans `.env.snapship` racine projet (clé
   `FIGMA_ACCESS_TOKEN` par défaut, override `wireframes.figma.token_env`).
   Chargé via `skills/_shared/load-env.sh` puis exporté dans l'env pour
   `figma-console-mcp` (paths REST fallback). Fichier gitignored. Voir
   [docs/config.md → Secrets](../config.md#secrets--envsnapship).
4. **File ouvert** : `figma-console-mcp` cible le fichier actuellement
   chargé dans l'onglet Desktop. Step-00 compare `figma.fileKey` avec
   `wireframes.figma.file_key` et halt si mismatch.

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
