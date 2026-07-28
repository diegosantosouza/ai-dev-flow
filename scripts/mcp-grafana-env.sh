#!/usr/bin/env bash
# mcp-grafana-env.sh — loads this repo's .env (if present) and execs mcp-grafana.
#
# Exists because MCP server `env:` values in agent frontmatter only expand from
# variables already exported in the shell that launched `claude` — there is no
# native way for an MCP server config to read an arbitrary .env file. This wrapper
# bridges that gap: agents point their mcpServers.grafana.command at this script
# (via the install-time-rendered absolute path) instead of at `mcp-grafana` directly.
#
# Values already exported in the parent shell still work — .env only fills gaps
# or overrides, it never removes an inherited variable.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_ROOT/.env"

if [ -f "$ENV_FILE" ]; then
  # Filter to a real temp file rather than `source <(...)` — bash 3.2 (macOS's
  # stock /bin/bash) silently sources nothing when given a process-substitution fd.
  FILTERED_ENV="$(mktemp)"
  trap 'rm -f "$FILTERED_ENV"' EXIT
  # Skip blank assignments (KEY=) so an unfilled .env placeholder never clobbers a
  # same-named variable already exported in the parent shell.
  # `|| true`: grep exits 1 when every line is filtered out (e.g. an all-blank .env),
  # which is a valid outcome here, not an error — set -e must not treat it as one.
  grep -v -E '^\s*[A-Za-z_][A-Za-z0-9_]*=\s*$' "$ENV_FILE" > "$FILTERED_ENV" || true
  set -a
  # shellcheck disable=SC1090
  source "$FILTERED_ENV"
  set +a
fi

command -v mcp-grafana >/dev/null 2>&1 || {
  echo "error: 'mcp-grafana' not found on PATH. Install it: https://github.com/grafana/mcp-grafana#installation" >&2
  exit 1
}

exec mcp-grafana --disable-write
