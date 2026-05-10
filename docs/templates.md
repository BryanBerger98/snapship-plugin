# Templates docs par défaut (bundlés)

Localisation: `~/.claude/skills/_shared/templates/docs-defaults/` (partagés `/define` + `/wireframe`).

Templates compatibles AFFiNE et Notion (markdown standard, conversion automatique).

Si user n'a pas créé de pages templates, skill propose pousser depuis markdown bundlé:

## Templates disponibles

**`prd-feature.md`** — variables `{feature_id}`, `{feature_title}`, `{feature_status}`, `{owner}`, `{target_release}`, `{problem_statement}`, `{solution_overview}`, `{in_scope}`, `{out_of_scope}`, `{user_flow}`, `{updated_at}`, plus blocs `{{#acceptance_criteria}}`, `{{#user_segments}}`, `{{#edge_cases}}`, `{{#error_states}}`, `{{#wireframes}}`, `{{#tickets}}`, `{{#open_questions}}`. Format change-request (v0.2 — figé post-ship, archivé `{prd_root}/{YYYY}/{MM-YYYY}/{NN-feature}`).

**`wireframes-gallery.md`** — variables `{feature_name}`, `{screens_blocks}` (loop: titre + image embed + liens)

> v0.1 `prd-global.md` retiré : la "global PRD" est remplacée par les domain pages générées idempotemment par `/snap:doc-import` ou `/snap:define` (étape publish).

## Push initial

Push via `docs-adapter.sh apply-template` au premier setup, puis dupliqué à chaque usage.

## Templates additionnels (autres usages)

- `_shared/templates/pr-default.md` — fallback PR template si `repository.pr_template_path` absent (sections Summary / Test plan / Tickets liés)
- `_shared/templates/daemon.sh.tpl` — template script daemon généré par `/develop --loop=daemon`
- `_shared/templates/session-start-hook.sh.tpl` — template hook SessionStart opt-in (copie user-side)
