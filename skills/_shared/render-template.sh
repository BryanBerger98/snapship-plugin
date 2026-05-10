#!/usr/bin/env bash
# render-template.sh — Mustache-subset template renderer for snap templates.
#
# Reads a template file with {{var}} / {{#list}}…{{/list}} / {{^var}}…{{/var}}
# placeholders and a JSON context (file or --vars), emits the rendered document
# on stdout. Implementation defers to a small embedded Python script (python3 is
# present on every supported platform: macOS 13+, ubuntu-latest, debian, alpine
# with python3 package).
#
# Supported syntax (deliberately small subset):
#   {{var}}          → top-level scalar substitution (HTML-NOT-escaped; output is markdown)
#   {{&var}}         → alias of {{var}} (Mustache compatibility)
#   {{#list}}…{{/list}}
#                    → iterate JSON array; inside, {{.}} is the current item if scalar,
#                      or {{key}} pulls a property if object. Nested sections supported.
#   {{^var}}…{{/var}} → render block iff var is null/false/missing/empty-string/empty-array
#   {{!comment}}     → stripped
#
# NOT supported: lambdas, partials, dotted paths.
#
# Usage:
#   render-template.sh --template=PATH --context=FILE.json
#   render-template.sh --template=PATH --vars='{"k":"v"}'
#   render-template.sh --vars='…' < template.md
#
# Exit codes: 0=ok, 1=missing template/context, 2=bad args, 3=unresolved required var.

set -euo pipefail

TEMPLATE=""
CONTEXT_FILE=""
VARS_INLINE=""
STRICT=false

usage() {
  cat <<'EOF'
Usage: render-template.sh --template=PATH (--context=FILE | --vars=JSON) [--strict]

Render a mustache-subset template to stdout.

Options:
  --template=PATH       Template file path (default: stdin if missing).
  --context=FILE        JSON context file (object).
  --vars=JSON           Inline JSON context (mutually exclusive with --context).
  --strict              Exit 3 if any {{var}} resolves to null/missing.
  -h, --help            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --template=*) TEMPLATE="${1#--template=}" ;;
    --context=*)  CONTEXT_FILE="${1#--context=}" ;;
    --vars=*)     VARS_INLINE="${1#--vars=}" ;;
    --strict)     STRICT=true ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 required" >&2; exit 1; }

if [ -n "$CONTEXT_FILE" ] && [ -n "$VARS_INLINE" ]; then
  echo "ERROR: --context and --vars are mutually exclusive" >&2
  exit 2
fi
if [ -z "$CONTEXT_FILE" ] && [ -z "$VARS_INLINE" ]; then
  echo "ERROR: --context or --vars required" >&2
  exit 2
fi

if [ -n "$CONTEXT_FILE" ]; then
  [ -f "$CONTEXT_FILE" ] || { echo "ERROR: context file not found: $CONTEXT_FILE" >&2; exit 1; }
  CTX_JSON=$(cat "$CONTEXT_FILE")
else
  CTX_JSON="$VARS_INLINE"
fi

if [ -n "$TEMPLATE" ]; then
  [ -f "$TEMPLATE" ] || { echo "ERROR: template not found: $TEMPLATE" >&2; exit 1; }
  TPL=$(cat "$TEMPLATE")
else
  TPL=$(cat)
fi

STRICT_FLAG=0
[ "$STRICT" = "true" ] && STRICT_FLAG=1

CTX_JSON="$CTX_JSON" TPL="$TPL" STRICT_FLAG="$STRICT_FLAG" python3 - <<'PY'
import json, os, re, sys

ctx = json.loads(os.environ["CTX_JSON"])
tpl = os.environ["TPL"]
strict = os.environ.get("STRICT_FLAG") == "1"

# Strip comments first.
tpl = re.sub(r"\{\{!.*?\}\}", "", tpl, flags=re.DOTALL)

def is_falsy(v):
    return v is None or v is False or v == "" or v == [] or v == {}

# Inverted sections {{^name}}…{{/name}}.
def render_inverted(s, scope):
    pattern = re.compile(r"\{\{\^([A-Za-z_][A-Za-z0-9_]*)\}\}(.*?)\{\{/\1\}\}", re.DOTALL)
    while True:
        m = pattern.search(s)
        if not m:
            return s
        name, body = m.group(1), m.group(2)
        v = scope.get(name) if isinstance(scope, dict) else None
        repl = body if is_falsy(v) else ""
        s = s[:m.start()] + repl + s[m.end():]

# Sections {{#name}}…{{/name}} (handles nested by re-rendering body for each item).
def render_sections(s, scope):
    pattern = re.compile(r"\{\{#([A-Za-z_][A-Za-z0-9_]*)\}\}(.*?)\{\{/\1\}\}", re.DOTALL)
    while True:
        m = pattern.search(s)
        if not m:
            return s
        name, body = m.group(1), m.group(2)
        items = scope.get(name) if isinstance(scope, dict) else None
        rendered = ""
        if isinstance(items, list):
            for item in items:
                if isinstance(item, dict):
                    chunk = render_inverted(body, item)
                    chunk = render_sections(chunk, item)
                    chunk = render_scalars(chunk, item, parent=scope)
                else:
                    # Scalar item: substitute {{.}} only.
                    chunk = body.replace("{{.}}", str(item))
                rendered += chunk
        s = s[:m.start()] + rendered + s[m.end():]

def render_scalars(s, scope, parent=None):
    def repl(m):
        key = m.group(1)
        if scope is not None and isinstance(scope, dict) and key in scope:
            v = scope[key]
        elif parent is not None and isinstance(parent, dict) and key in parent:
            v = parent[key]
        else:
            return m.group(0)  # leave unresolved for strict-mode detection
        if v is None:
            return ""
        return str(v) if not isinstance(v, str) else v
    return re.sub(r"\{\{&?([A-Za-z_][A-Za-z0-9_]*)\}\}", repl, s)

tpl = render_inverted(tpl, ctx)
tpl = render_sections(tpl, ctx)
tpl = render_scalars(tpl, ctx)

if strict:
    leftover = re.findall(r"\{\{[^}]+\}\}", tpl)
    leftover = [x for x in leftover if not x.startswith("{{!")]
    if leftover:
        sys.stderr.write("ERROR: unresolved placeholders: " + " ".join(sorted(set(leftover))) + "\n")
        sys.exit(3)

sys.stdout.write(tpl)
PY
