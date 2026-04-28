#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "ai-dev-flow uninstaller"
echo ""

unlink_file() {
  local src="$1"
  local dst="$2"
  local name
  name="$(basename "$dst")"

  if [ -L "$dst" ]; then
    local current
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      rm "$dst"
      echo "  removed $name"
      # restore backup if exists
      if [ -f "${dst}.bak" ]; then
        mv "${dst}.bak" "$dst"
        echo "  restored $name from backup"
      fi
      return
    fi
  fi
  echo "  skip   $name (not managed by ai-dev-flow)"
}

echo "agents:"
for f in "$REPO_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  unlink_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done

echo ""
echo "commands:"
for f in "$REPO_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  unlink_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
done

echo ""
echo "skills:"
for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  src="${d%/}"
  dst="$CLAUDE_DIR/skills/$name"
  if [ -L "$dst" ]; then
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      rm "$dst"
      echo "  removed $name"
      if [ -d "${dst}.bak" ]; then
        mv "${dst}.bak" "$dst"
        echo "  restored $name from backup"
      fi
    else
      echo "  skip   $name (not managed by ai-dev-flow)"
    fi
  else
    echo "  skip   $name (not a symlink)"
  fi
done

echo ""
echo "CLAUDE.md:"
unlink_file "$REPO_DIR/.CLAUDE.md.rendered" "$CLAUDE_DIR/CLAUDE.md"

echo ""
echo "hooks:"
unlink_file "$REPO_DIR/scripts/pre-commit.sh" "$REPO_DIR/.git/hooks/pre-commit"

# --- settings.json (remove model) ---

echo ""
echo "settings:"

if [ -f "$SETTINGS_FILE" ] && command -v jq &>/dev/null; then
  CURRENT_MODEL=$(jq -r '.model // empty' "$SETTINGS_FILE")
  if [ "$CURRENT_MODEL" = "opusplan" ]; then
    jq 'del(.model)' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    echo "  removed model (was opusplan)"
  else
    echo "  skip   model (not set by ai-dev-flow)"
  fi
else
  echo "  skip   settings.json (not found or jq unavailable)"
fi

echo ""
echo "done."
