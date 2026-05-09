#!/usr/bin/env bash
# filter-ui-tickets.sh — Identify UI tickets in tickets.json (heuristic).
#
# A ticket is "UI" if any of:
#   1. files[] entry matches *.tsx|.jsx|.vue|.svelte|.astro|.html|.htm|.css|.scss
#      or path token components/|pages/|app/|views/|screens/|routes/
#   2. title or description matches UI keyword regex (case-insensitive)
#   3. wireframe_screen already set
#
# Emits a JSON array on stdout:
#   [
#     {"local_id":"t-001","title":"Signup screen","screen_hint":"signup-screen"},
#     ...
#   ]
#
# screen_hint = first matching keyword/path token, normalised:
#   - keyword match → "<keyword>-screen" (e.g. "signup" → "signup-screen") when
#     the keyword itself is in {screen,page,view,modal,dialog,form} stripped from
#     adjacent token, otherwise the bare keyword.
#   - path token match → directory token (components|pages|...) without slash.
#   - wireframe_screen already set → its existing value.
#
# Usage:
#   filter-ui-tickets.sh --tickets-file=PATH
#
# Exit codes: 0=ok (array may be empty), 1=missing/invalid file, 2=bad args.

set -euo pipefail

TICKETS_FILE=""

usage() {
  cat <<'EOF'
Usage: filter-ui-tickets.sh --tickets-file=PATH

Filter UI-impacting tickets from a feature tickets.json.

Options:
  --tickets-file=PATH   Required. Path to tickets.json.
  -h, --help            Show this help.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tickets-file=*) TICKETS_FILE="${1#--tickets-file=}" ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

[ -z "$TICKETS_FILE" ] && { echo "ERROR: --tickets-file required" >&2; exit 2; }
[ -f "$TICKETS_FILE" ] || { echo "ERROR: tickets file not found: $TICKETS_FILE" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 1; }

jq -e 'has("tickets") and (.tickets | type == "array")' "$TICKETS_FILE" >/dev/null \
  || { echo "ERROR: invalid tickets.json (missing tickets[])" >&2; exit 1; }

# Heuristic via jq. Three predicates → first matching hint wins.
jq '
  def file_ext_re: "\\.(?<ext>tsx|jsx|vue|svelte|astro|html|htm|css|scss)$";
  def path_token_re: "(^|/)(?<dir>components|pages|app|views|screens|routes)/";
  def keyword_re:
    "(?<kw>signup|login|signin|signout|logout|register|verify|onboarding|onboard|dashboard|profile|settings|search|checkout|cart|payment|screen|page|view|modal|dialog|form|button|layout|navigation|nav|header|footer|sidebar|drawer|toast|empty[ _-]?state|loading[ _-]?state|error[ _-]?state)";

  def first_file_hint(files):
    (files // [])
    | map(select(test(file_ext_re; "i")) // false)
    | .[0] // null;

  def first_path_token(files):
    (files // [])
    | map(capture(path_token_re; "i").dir? // empty)
    | .[0] // null;

  def keyword_hint(text):
    (text // "")
    | (capture(keyword_re; "i").kw? // null);

  def normalise_hint($raw; $kind):
    if $raw == null then null
    elif $kind == "path" then ($raw | ascii_downcase)
    else
      ($raw | ascii_downcase | gsub("[ _]"; "-")) as $w
      | if ($w | test("-(screen|page|view)$")) then $w
        elif ($w | IN("screen","page","view","modal","dialog","form","button","layout","nav","navigation","header","footer","sidebar","drawer","toast")) then "\($w)-section"
        else "\($w)-screen"
        end
    end;

  def derive_hint(t):
    if (t.wireframe_screen // "") != "" then t.wireframe_screen
    else
      (first_file_hint(t.files)) as $f
      | (first_path_token(t.files)) as $p
      | (keyword_hint(t.title)) as $kt
      | (keyword_hint(t.description)) as $kd
      | if $kt != null then normalise_hint($kt; "kw")
        elif $kd != null then normalise_hint($kd; "kw")
        elif $p != null then normalise_hint($p; "path")
        elif $f != null then "screen"
        else null
        end
    end;

  def is_ui(t):
    ((t.wireframe_screen // "") != "")
    or ((t.files // []) | any(test(file_ext_re; "i")))
    or ((t.files // []) | any(test(path_token_re; "i")))
    or (((t.title // "") | test(keyword_re; "i")))
    or (((t.description // "") | test(keyword_re; "i")));

  [ .tickets[]
    | select(is_ui(.))
    | {local_id, title, screen_hint: derive_hint(.)}
  ]
' "$TICKETS_FILE"
