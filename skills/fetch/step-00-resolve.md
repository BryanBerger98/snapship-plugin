---
step: 00-resolve
next_step: 01-fetch
description: Parse args, enumère features + kinds à fetch, lit chaque manifest pour récupérer la liste des refs distantes à pull.
---

# step-00 — resolve fetch targets

## Tâches

1. **Parse args** `/snap:fetch` :
   - `--feature=SLUG`, `--kind=K|all`, `--all`, `--check`, `--dry-run`.
   - Validation : `--feature` ET `--all` mutuellement exclusifs.
   - Sans `--feature` ni `--all` → ERROR avec aide.

2. **Lit config** (`bash skills/_shared/load-config.sh`) :
   - `documentation.platform` (notion/affine/none)
   - `tickets.platform`
   - `design.platform` (penpot/figma)
   - Si `--kind=tickets` ET `tickets.platform == none` → BLOCK.

3. **Énumère features** :
   ```bash
   if [ -n "$FEATURE" ]; then
     FEATURES=("$FEATURE")
   else
     FEATURES=($(ls .snap/manifests/*.manifest.json | xargs -n1 basename | sed 's/\.manifest\.json$//'))
   fi
   ```

4. **Énumère kinds par feature** :
   - `--kind=prd` → `[prd]`
   - `--kind=design` → `[design_gallery, design_file]`
   - `--kind=wireframe` → `[wireframes_gallery]`
   - `--kind=tickets` → `[tickets]`
   - `--kind=all` (défaut feature) → tout ce qui existe dans `manifest.refs.*`

5. **Build plan JSON** :
   ```json
   {
     "mode": "fetch" | "check",
     "dry_run": false,
     "targets": [
       { "story_id": "01-auth", "kind": "prd",
         "ref": { "platform":"notion", "page_id":"abc", "synced_at":"..." } },
       ...
     ],
     "taxonomy_refresh": true   // toujours, si --all
   }
   ```
   Persiste dans `.snap/.fetch-plan.json` (ephémère).

6. **Mode `--check`** : sortie immédiate post-step-00 avec compare logic
   (court-circuite step-01/02/03) :
   ```bash
   for target in $TARGETS; do
     # pull last_edited_time uniquement (cheap MCP call)
     # compare to ref.synced_at
     # if remote > local → sync-fetch.sh check-mark
   done
   ```

7. **Telemetry + progress** :
   ```bash
   bash skills/_shared/progress.sh start --skill=fetch --story-id=_global
   bash skills/_shared/progress.sh step --skill=fetch --story-id=_global \
     --step-num=00 --step-name=resolve --status=ok
   ```

## Continue à

`step-01-fetch.md` (sauf `--check` → step-05 finish-like direct).
