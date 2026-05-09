# Templates docs par défaut (bundlés)

Localisation: `~/.claude/skills/_shared/templates/docs-defaults/` (partagés `/define` + `/wireframe`).

Templates compatibles AFFiNE et Notion (markdown standard, conversion automatique).

Si user n'a pas créé de pages templates, skill propose pousser depuis markdown bundlé:

## Templates disponibles

**`prd-global.md`** — variables `{product_name}`, `{vision}`, `{problem}`, `{users}`, `{features_table}`, `{out_of_scope}`

**`prd-feature.md`** — variables `{feature_name}`, `{vision}`, `{scope}`, `{capabilities}`, `{phases}`, `{out_of_scope}`, `{code_refs}`

**`wireframes-gallery.md`** — variables `{feature_name}`, `{screens_blocks}` (loop: titre + image embed + liens)

## Push initial

Push via `docs-adapter.sh apply-template` au premier setup, puis dupliqué à chaque usage.

## Templates additionnels (autres usages)

- `_shared/templates/pr-default.md` — fallback PR template si `repository.pr_template_path` absent (sections Summary / Test plan / Tickets liés)
- `_shared/templates/daemon.sh.tpl` — template script daemon généré par `/develop --loop=daemon`
- `_shared/templates/session-start-hook.sh.tpl` — template hook SessionStart opt-in (copie user-side)
