#!/usr/bin/env bash
# Validates frontmatter of all agent .md files in the given directory.
# Usage: validate-agents.sh [agents-dir]
# Exit 0 if all pass, exit 1 if any fail.
#
# Checks per file:
#   - starts with YAML frontmatter (first line ---)
#   - has required fields: name, description (spec-required)
#   - has model, effort (this toolkit's stricter convention)
#   - model value is a known alias (haiku|sonnet|opus|fable|inherit) or a full id (claude-*)
#   - effort value is one of: low|medium|high|xhigh|max
# Sources: https://code.claude.com/docs/en/sub-agents , https://code.claude.com/docs/en/model-config
set -euo pipefail

AGENTS_DIR="${1:-$(cd "$(dirname "$0")/.." && pwd)/agents}"

ERRORS=0

# field_value <file> <field>  -> prints the trimmed value, empty if absent
field_value() {
  grep -m1 "^$2:" "$1" 2>/dev/null | sed "s/^$2:[[:space:]]*//" | sed 's/[[:space:]]*$//'
}

for f in "$AGENTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"

  if ! head -1 "$f" | grep -q "^---$"; then
    echo "  FAIL  $name: missing YAML frontmatter (first line must be ---)"
    ERRORS=$((ERRORS + 1))
  fi

  # required fields (spec)
  for field in name description; do
    if ! grep -q "^$field:" "$f"; then
      echo "  FAIL  $name: missing required field '$field'"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # required fields (toolkit convention)
  for field in model effort; do
    if ! grep -q "^$field:" "$f"; then
      echo "  FAIL  $name: missing required field '$field'"
      ERRORS=$((ERRORS + 1))
    fi
  done

  # value validation (only when the field is present)
  if grep -q "^model:" "$f"; then
    model_val="$(field_value "$f" model)"
    case "$model_val" in
      haiku|sonnet|opus|fable|inherit) ;;
      claude-*) ;;
      *) echo "  FAIL  $name: invalid model '$model_val' (expected haiku|sonnet|opus|fable|inherit or claude-*)"
         ERRORS=$((ERRORS + 1)) ;;
    esac
  fi

  if grep -q "^effort:" "$f"; then
    effort_val="$(field_value "$f" effort)"
    case "$effort_val" in
      low|medium|high|xhigh|max) ;;
      *) echo "  FAIL  $name: invalid effort '$effort_val' (expected low|medium|high|xhigh|max)"
         ERRORS=$((ERRORS + 1)) ;;
    esac
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s) in agent frontmatter. Fix before committing."
  exit 1
fi

echo "  OK    all agent frontmatter checks passed"
