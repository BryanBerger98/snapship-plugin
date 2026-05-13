# Skill `/design`

Génère maquettes haute-fidélité (mockups), bootstrap ou patch un design system via Penpot ou Figma. **Optionnel**, parallèle ou séquentiel à `/wireframe`.

## Frontmatter

```yaml
name: design
description: Génère maquettes hi-fi (Penpot/Figma) — 3 modes (ds-init, ds-update, mockup). Optionnel, parallèle ou séquentiel à /wireframe. Lie les tickets UI aux assets design.
argument-hint: "[-r] [--feature=ID] [--mode=ds-init|ds-update|mockup] [--dry-run]"
```

## Modes

| Mode         | Usage                                                                                              | Trigger typique                                          |
|--------------|----------------------------------------------------------------------------------------------------|----------------------------------------------------------|
| `ds-init`    | Bootstrap un design system file depuis `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml` | Premier run, pas de DS file configuré                    |
| `ds-update`  | Diff DS specs vs fichier courant → patch en place (upsert composants par nom)                      | Specs modifiées, DS file out-of-date                     |
| `mockup`     | Par screen×state : frame hi-fi, applique composants DS, exporte asset, lie aux tickets             | Après `/ticket` (optionnellement après `/wireframe`)     |

`step-00` auto-résout le mode. Si ambigu → `AskUserQuestion`.

## Flags

- `-r` resume (state per-mode)
- `--feature=ID` (requis pour `mockup` si plusieurs features ; partial-match)
- `--mode=...` force un mode (sinon auto-résolu)
- `--dry-run` helpers retournent descripteurs mock, pas de MCP call, pas d'asset écrit

## Plateformes supportées

| `design.platform` | Helper                                  | Backend                                                                                       |
|-------------------|-----------------------------------------|-----------------------------------------------------------------------------------------------|
| `penpot`          | `skills/_shared/penpot-helper.sh`       | Même MCP que `/wireframe penpot` — skill applique composants hi-fi (fidélité contrôlée skill) |
| `figma`           | `skills/_shared/figma-bridge-helper.sh` | `bridge-ds compile` (YAML CSpec → JS Plugin API) + transport `official` (`figma_execute`) ou `console` (collage manuel DevTools) |
| `none` (absent)   | —                                       | Skill skippé (exit 0 silencieux)                                                              |

`frame0` est **exclu** — Frame0 low-fi only.

Helpers context-agnostic depuis v0.5 : aucune lecture de config — `step-00` résout les valeurs (`file_id`, `file_key`, `bridge_kb_path`, `bridge_transport`, `token_env`, `export_format`, `design_system_page`) et les passe explicitement à chaque appel.

## Préflight (step-00)

- **Penpot** : `penpot-helper.sh get-current-file` compare `penpot.currentFile.id` à `design.penpot.file_id`. Mismatch → halt clair. Vide → flow auto-link (§Auto-link).
- **Figma** : variable env `$FIGMA_ACCESS_TOKEN` (ou `design.figma.token_env`) requise. `figma-helper.sh get-current-file` compare `figma.fileKey` à `design.figma.file_key`. Mismatch → halt. CLI `bridge-ds` joignable (sinon `npm i -g @noemuch/bridge-ds`).
- **MCP** : `check-mcp-required.sh --skill=design` — serveur MCP correspondant doit répondre.

## Auto-link wireframes ↔ design

Si `wireframes.platform == design.platform` ET binding wireframes défini ET `design.{plat}.{file_id|file_key}` null → `AskUserQuestion` step-00 :

- **Yes, reuse same file** → copie binding `wireframes` → `design.{plat}`
- **No, separate design file** → prompt binding distinct
- **Save to config** → persiste

## Pipeline

| #  | Step                          | Mode actif                | Rôle                                                                                                              |
|----|-------------------------------|---------------------------|-------------------------------------------------------------------------------------------------------------------|
| 00 | `step-00-init`                | tous                      | Parse args, resolve feature+mode, load nested config, préflight platform, auto-link si match                      |
| 01 | `step-01-ds-bootstrap`        | `ds-init` / `ds-update`   | Penpot → `add-shapes` upsert YAML ; Figma → Bridge compile → transport `official`/`console` ; cache `.design-cache.json` |
| 02 | `step-02-source-resolve`      | `mockup`                  | Détecte wireframes existants par feature → décide `mockup` vs `reused` par screen                                 |
| 03 | `step-03-mockup`              | `mockup`                  | Par `(screen_id, state)` : frame hi-fi, applique composants DS, exporte asset                                     |
| 04 | `step-04-gallery`             | `mockup`                  | Page Docs `Design — {feature_title}` séparée de `wireframes-gallery` ; blob-upload assets                         |
| 05 | `step-05-link`                | `mockup`                  | Patch chaque UI ticket : `design_screen`, `design_url`, `design_mode` (`mockup|reused`) ; revalide schema         |

Modes `ds-init` / `ds-update` s'arrêtent après step-01.

## Penpot MCP tools utilisés

- `execute_code` — pages, shapes, composants (mêmes globals que `/wireframe` : `penpot`, `penpotUtils`, `storage`).
- `export_shape` — export PNG/SVG, `filePath` **absolu** requis.
- Page `design.penpot.design_system_page` (défaut `Components`) lue en mockup, écrite en `ds-*`.

## Figma — Bridge CLI + figma-console-mcp

- **Bridge CLI** (`@noemuch/bridge-ds`, MIT v3.0.0) — compile YAML CSpec → JS Plugin API conforme système design (26 règles Figma).
- **figma-console-mcp** — outil `figma_execute` injecte le JS compilé dans Figma Desktop via Bridge plugin (WebSocket 9223–9232).
- **Transport** :
  - `official` (défaut) — Bridge → JS → `figma_execute` automatique.
  - `console` — Bridge écrit `.design-cache/<feature>-<step>.js`, skill affiche "paste in DevTools" + `AskUserQuestion`.
- **KB** (`design.figma.bridge_kb_path`) — base de connaissance Bridge sur disque ; `extract-ds` rafraîchit depuis le DS file live.

### Prérequis Figma

1. **Figma Desktop** lancé (Bridge plugin n'existe que sur Desktop).
2. **Desktop Bridge plugin** chargé : Plugins → Browse → "Desktop Bridge" → Open. Maintient WebSocket interrogé par `figma-console-mcp`.
3. **Token Figma** dans `$FIGMA_ACCESS_TOKEN` (ou variable nommée `design.figma.token_env`).
4. **DS file ouvert** pour `ds-*`, ou **DS + mockup target** pour `mockup`. step-00 vérifie `figma.fileKey == design.figma.file_key`.

## Outputs

- **`ds-init`** — DS file populé (atomic/molecular/organism). `file_id`/`file_key` caché dans config si "Save to config" choisi.
- **`ds-update`** — DS file patché in place. `specs_hash` mis à jour dans `.design-cache.json`.
- **`mockup`** :
  - `.claude/product/features/{feature_id}/design/{screen-id}-{state}.{fmt}` (cache local).
  - Page Docs `Design — {feature_title}` (URL cachée `design_gallery.{feature_id}` dans `.docs-cache.json`).
  - Chaque UI ticket gagne `design_screen`, `design_url`, `design_mode`.

## Templates bundlés

- `_shared/templates/docs-defaults/design-gallery.md` — layout gallery markdown.
- `_shared/templates/design-system-defaults/{atomic,molecular,organism}.yaml` — base YAML CSpec (Bridge-compatible, lisible par `penpot-helper add-shapes`).

User override : copier dans `design-system/specs/*.yaml` à la racine projet.

## Resume

Même pattern que `/wireframe` : `/design --resume` délègue à `resume-state.sh next --skill=design`. State keyed `(skill=design, feature_id, mode)` — les 3 modes resument indépendamment.

## Wiring

- **`/develop` step-00** — banner designer-handoff si `tickets[].design_url` présent (non bloquant si absent).
- **`/qa` step-04** — option `design_check` (compare implem vs design asset si présent, opt-in `qa.design_check.enabled`). Mode `asset-presence` (défaut) ou `playwright` (futur).
- **`/snap:doc-update`** — ingère assets design en plus des wireframes dans bundles journey.
- **Lifecycle scripts** — `pre_design` / `post_design` supportés.

## Acceptance check

- **`ds-init`** — DS file populé, file id/key caché.
- **`ds-update`** — DS file patché, diff résumé caché.
- **`mockup`** — chaque UI ticket flagué step-02 a `design_url`, `design-gallery.md` existe sous `.claude/product/`, une section par screen + une ligne par state.
