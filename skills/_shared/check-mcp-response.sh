#!/usr/bin/env bash
# check-mcp-response.sh — validate the JSON envelope returned by docs-adapter
# (and other MCP-bridging helpers) before consumers extract identifiers from
# it. Prevents `refs.prd` (or `_taxonomy.json`) from being acked with a null
# `page_id` / `url` when the adapter actually failed.
#
# Usage:
#   check-mcp-response.sh JSON KEY
#     JSON   — raw response payload (must parse as a JSON object).
#     KEY    — top-level field whose value must be a non-empty string.
#
# Rules (checked in order):
#   1. JSON parses as an object               → else rc=1, stderr `mcp: malformed-json`.
#   2. Object has no `.error` key             → else rc=1, stderr `mcp: error: <reason>`.
#   3. `.KEY` is present, non-null, non-empty → else rc=1, stderr `mcp: missing <KEY>`
#                                                or `mcp: empty <KEY>`.
#
# On success: prints the captured value on stdout, rc=0.
# On usage error (wrong arg count): rc=2.

set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "ERROR: check-mcp-response.sh JSON KEY" >&2
  exit 2
fi

JSON="$1"
KEY="$2"

# 1. Well-formed JSON object.
if ! echo "$JSON" | jq -e 'type == "object"' >/dev/null 2>&1; then
  echo "mcp: malformed-json" >&2
  exit 1
fi

# 2. Reject adapter-side errors.
ERR=$(echo "$JSON" | jq -r '.error // empty')
if [ -n "$ERR" ]; then
  echo "mcp: error: $ERR" >&2
  exit 1
fi

# 3. Required key present + non-null + non-empty string.
HAS=$(echo "$JSON" | jq --arg k "$KEY" 'has($k)')
if [ "$HAS" != "true" ]; then
  echo "mcp: missing $KEY" >&2
  exit 1
fi
VAL=$(echo "$JSON" | jq -r --arg k "$KEY" '.[$k] // empty')
if [ -z "$VAL" ]; then
  echo "mcp: empty $KEY" >&2
  exit 1
fi

printf '%s\n' "$VAL"
