# Dogfooding v0.1.0

Notes friction collectées pendant validation projet pilote `snapship-plugin-test`
(side-project greenfield, GitHub tickets, 1 feature simple "Bouton login simple").

Format entrée: `Step | Severity | Issue | Fix/Status`.

Severity: **P0** = bloque le workflow, **P1** = friction notable, **P2** = polish.

## /snap:init

| Step | Severity | Issue | Fix/Status |
|------|----------|-------|------------|
| (post-init) | P1 | `/snap:init` ne génère/templatise pas `.mcp.json`. User doit deviner noms binaires exacts (`affine-mcp-server`, `frame0-mcp-server`, etc.). Pilote a mis `command: "affine-mcp"` → server fail start → step-05 publish fail downstream. | À faire v0.2: ajouter step `init/step-02-mcp.md` qui génère/merge `.mcp.json` selon plateformes choisies. v0.1 workaround: doc README explicite. |

## /snap:define

| Step | Severity | Issue | Fix/Status |
|------|----------|-------|------------|
| 05-publish | P0 | Logué `skip: documentation.platform=none` alors que `.config-resolved.json` ligne 56-57 a `documentation.platform=affine`. Root cause: step-05 task A ne fournissait pas commande bash explicite — model a hallucinated/misread la valeur (probable fallback `none` par défaut). | ✅ Fix: ajout bloc bash déterministe `jq -r '.documentation.platform // "none"' .claude/product/.config-resolved.json` + abort sur missing field. Same fix appliqué à `wireframe/step-03-gallery.md` (même pattern). |
| 05-publish (run 2) | P0 | Après fix précédent: `mcp__affine__*` tools absents session car `.mcp.json` pilote utilise `command: "affine-mcp"` mais binaire npm s'appelle `affine-mcp-server`. Server fail start silencieux → 0 tools dispo → adapter exit 10 mais MCP tool unreachable → skill marque step-05 fail. | ✅ Skill detection correcte (fail loud, pas skip silent). Fix utilisateur: install `npm i -g affine-mcp-server` + corriger `.mcp.json` command + restart session. Cause racine workflow: plugin ne template pas `.mcp.json` (cf. friction init P1). |

## /snap:ticket

(à compléter)

## /snap:wireframe

(à compléter — feature non-UI possible, opt-in)

## /snap:develop

(à compléter)

## /snap:qa

(à compléter)

## Telemetry analyse

(à compléter post-cycle complet)
