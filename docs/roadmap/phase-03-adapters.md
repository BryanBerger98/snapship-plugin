# Phase 3 — Adapters

**Objectif:** abstraction MCP/CLI plateformes externes.

- [x] `docs-adapter.sh` — AFFiNE + Notion (get/create/apply-template/upload-blob/update/search)
- [x] `tickets-adapter.sh` — GitHub/GitLab/JIRA (create/get/update/comment/list)
- [x] `frame0-helper.sh` — wrapper batch ops Frame0 MCP
- [x] `penpot-helper.sh` — wrapper batch ops Penpot MCP (mirror frame0 action surface : `execute_code` pour CRUD/shapes, `export_shape` pour assets)
- [x] Mode `--dry-run` env var respecté par tous adapters (write ops → log skip)

**Sortie:** adapters interchangeables, write ops idempotentes.
