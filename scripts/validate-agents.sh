#!/usr/bin/env bash
# Validates frontmatter of all agent .md files in the given directory.
# Usage: validate-agents.sh [agents-dir]
# Exit 0 if all pass, exit 1 if any fail.
set -euo pipefail

AGENTS_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/agents}"

ERRORS=0

for f in "$AGENTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"

  if ! head -1 "$f" | grep -q "^---$"; then
    echo "  FAIL  $name: missing YAML frontmatter (first line must be ---)"
    ERRORS=$((ERRORS + 1))
  fi
  if ! grep -q "^model:" "$f"; then
    echo "  FAIL  $name: missing required field 'model'"
    ERRORS=$((ERRORS + 1))
  fi
  if ! grep -q "^effort:" "$f"; then
    echo "  FAIL  $name: missing required field 'effort'"
    ERRORS=$((ERRORS + 1))
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s) in agent frontmatter. Fix before committing."
  exit 1
fi

echo "  OK    all agent frontmatter checks passed"
