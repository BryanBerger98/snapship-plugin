# 🛠️ Contributing

Docs for people working **on** the plugin (not just with it).

## 🧭 Get oriented

- [**Architecture**](architecture.md) — skill anatomy, state machine, shared helpers
- [**Plugin manifest**](plugin-manifest.md) — `.claude-plugin/plugin.json`, distribution, layout
- [**Project structure**](structure.md) — file tree, `.snap/` storage, gitignore policy

## 🧱 Internals

- [**Shared scripts**](scripts.md) — contracts for `skills/_shared/*` helpers
- [**Templates**](templates.md) — bundled doc templates (PRD, wireframe gallery, …)

## 📜 History

- [**Decisions**](decisions.md) — validated decisions + rationale + history
- [**Changelog**](../../CHANGELOG.md) — release notes

## 🧪 Local dev quickstart

```bash
git clone https://github.com/BryanBerger98/snapship-plugin
cd snapship-plugin
bats tests/                       # unit + integration tests
./scripts/validate-plugin.sh      # plugin manifest sanity
shellcheck skills/**/*.sh         # shell hygiene
```

The CI workflow (`.github/workflows/validate.yml`) runs the same checks on every PR.

## 🤝 PRs welcome

- Open an issue first for substantial changes — see [`.github/ISSUE_TEMPLATE/`](../../.github/ISSUE_TEMPLATE/)
- Keep commits atomic, follow Conventional Commits
- Update [`CHANGELOG.md`](../../CHANGELOG.md) under the next release section
- Reference the relevant skill doc in [`usage/skills/`](../usage/skills/) when behaviour changes

---

> Looking for usage docs? → [Usage](../usage/README.md)
