#!/usr/bin/env bash
# Git pre-commit hook: validates agent frontmatter when agents/*.md are staged.
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel)"

if git diff --cached --name-only | grep -q "^agents/.*\.md$"; then
  "$REPO_ROOT/scripts/validate-agents.sh" "$REPO_ROOT/agents"
fi
