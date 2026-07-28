#!/usr/bin/env bash
# Validates frontmatter of all skills/<name>/SKILL.md files in the given directory.
# Usage: validate-skills.sh [skills-dir] [agents-dir]
# Exit 0 if all pass, exit 1 if any fail.
#
# Checks per skill:
#   - SKILL.md starts with YAML frontmatter (first line ---)
#   - has required fields: name, description
#   - 'name' matches the skill's directory name
#   - if 'agent:' is set, that agent exists in agents-dir
# Sources: https://code.claude.com/docs/en/skills
set -euo pipefail

SKILLS_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/skills}"
AGENTS_DIR="${2:-$(cd "$(dirname "$0")/.." && pwd)/agents}"

ERRORS=0

field_value() {
  grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

for d in "$SKILLS_DIR"/*/; do
  [ -d "$d" ] || continue
  name="$(basename "${d%/}")"
  f="$d/SKILL.md"

  if [ ! -f "$f" ]; then
    echo "  FAIL  $name: missing SKILL.md"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  if ! head -1 "$f" | grep -q "^---$"; then
    echo "  FAIL  $name: missing YAML frontmatter (first line must be ---)"
    ERRORS=$((ERRORS + 1))
  fi

  for field in name description; do
    if ! grep -q "^$field:" "$f"; then
      echo "  FAIL  $name: missing required field '$field'"
      ERRORS=$((ERRORS + 1))
    fi
  done

  if grep -q "^name:" "$f"; then
    name_val="$(field_value "$f" name)"
    if [ "$name_val" != "$name" ]; then
      echo "  FAIL  $name: field 'name' ('$name_val') does not match directory name"
      ERRORS=$((ERRORS + 1))
    fi
  fi

  if grep -q "^agent:" "$f"; then
    agent_val="$(field_value "$f" agent)"
    if [ ! -f "$AGENTS_DIR/$agent_val.md" ]; then
      echo "  FAIL  $name: references agent '$agent_val', which does not exist in $AGENTS_DIR"
      ERRORS=$((ERRORS + 1))
    fi
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s) in skill frontmatter. Fix before committing."
  exit 1
fi

echo "  OK    all skill frontmatter checks passed"
