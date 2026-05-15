---
step: 00-detect
next_step: 01-confirm
description: Détecte version courante workspace, version cible plugin, résout chaîne migrations. Détecte conditions (tickets sans tracker, daemon usage) qui activent décisions optionnelles.
---

# step-00 — detect versions + plan migration chain

Identifie où on part, où on va, et quelles migrations enchaîner.

## Tâches

1. **Parse args** `/snap:upgrade` : `--target=VERSION`, `--dry-run`, `--auto`, `--from=VERSION`.
   Défauts : `dry_run=false`, `auto=false`, `target=`(plugin version), `from=auto`.

2. **Lit version plugin** :
   ```bash
   PLUGIN_VERSION=$(jq -r '.version' .claude-plugin/plugin.json)
   ```
   Si `--target` absent, utilise `$PLUGIN_VERSION`.

3. **Détecte version courante workspace** (ordre de priorité) :
   ```bash
   if [ -f .snap/manifests/_taxonomy.json ]; then
     CUR=$(jq -r '.schema_version // ""' .snap/manifests/_taxonomy.json)
   fi
   if [ -z "$CUR" ] && ls .snap/manifests/*.manifest.json >/dev/null 2>&1; then
     CUR=$(jq -r '.schema_version // ""' .snap/manifests/*.manifest.json | head -1)
   fi
   if [ -z "$CUR" ] && [ -f snapship.config.json ]; then
     CUR=$(jq -r '.version // ""' snapship.config.json)
   fi
   if [ -z "$CUR" ] && [ -d .claude/product ]; then
     CUR="0.6.0"   # presumé
   fi
   if [ -z "$CUR" ]; then
     echo "ERROR: Pas de workspace snap détecté. Run /snap:init."
     exit 1
   fi
   ```
   Si `--from` passé, override `$CUR`.

4. **Résout chaîne migrations** depuis
   `skills/_shared/migrations/registry.json` :
   - Filtre `migrations[]` dont `from` ≥ `$CUR` et `to` ≤ `$TARGET`.
   - Trie par `to` ascendant (semver).
   - Si chaîne vide ET `$CUR == $TARGET` → déjà à jour, exit 0 (suggère
     `/snap:fetch` si user veut quand même resync).
   - Si chaîne vide ET `$CUR != $TARGET` → ERROR "Pas de chemin migration de
     `$CUR` vers `$TARGET`. Versions disponibles : ...".

5. **Détecte conditions** activant décisions optionnelles :
   - `tickets_platform_missing` : `jq -r '.tickets.platform // ""' snapship.config.json`
     vide ou `inherit` non résolu.
   - `daemon_referenced` : grep `--loop=daemon` ou `daemon.sh` dans `.claude/`,
     `scripts/`, `*.sh`, `Makefile`, `package.json`.

6. **Build plan JSON** (passe à step-01) :
   ```json
   {
     "from": "0.6.0",
     "target": "1.0.0",
     "dry_run": false,
     "auto": false,
     "chain": [
       { "script": "v0.6.0_to_v1.0.0.sh", "breaking": true, "summary": "...", "decisions": [...] }
     ],
     "conditions": { "tickets_platform_missing": true, "daemon_referenced": false }
   }
   ```

7. **Telemetry** :
   ```bash
   bash skills/_shared/telemetry.sh log --skill=upgrade --step-num=00 --step-name=detect --status=ok \
     --extra="$(jq -nc --arg f "$CUR" --arg t "$TARGET" --argjson n "$(echo "$CHAIN" | jq 'length')" \
       '{from:$f, target:$t, migrations:$n}')"
   ```

8. **Progress** :
   ```bash
   bash skills/_shared/progress.sh start --skill=upgrade --feature-id=_global
   bash skills/_shared/progress.sh step --skill=upgrade --feature-id=_global \
     --step-num=00 --step-name=detect --status=ok
   ```

## Output attendu (passe au step suivant)

JSON plan stringifié, persisté dans `.snap/.upgrade-plan.json` (ephémère,
gitignoré, trash après step-05).

## Continue à

`step-01-confirm.md`.
