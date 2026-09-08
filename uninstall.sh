#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# shellcheck source=scripts/link-lib.sh
. "$REPO_DIR/scripts/link-lib.sh"
link_lib_init

AGENTS_RENDERED_DIR="$REPO_DIR/.agents.rendered"
CLAUDE_MD_RENDERED="$REPO_DIR/.CLAUDE.md.rendered"

echo "ai-dev-flow uninstaller"
echo "platform: $PLATFORM"
echo ""

restore_backup() { # dst
  if [ -e "$1.bak" ]; then
    mv "$1.bak" "$1"
    echo "  restored $(basename "$1") from backup"
  fi
}

unlink_file() {
  local src="$1"
  local dst="$2"
  local name
  name="$(basename "$dst")"

  if is_file_linked "$src" "$dst"; then
    rm "$dst"
    echo "  removed $name"
    restore_backup "$dst"
  else
    echo "  skip   $name (not managed by ai-dev-flow)"
  fi
}

unlink_dir() {
  local src="$1"
  local dst="$2"
  local name
  name="$(basename "$dst")"

  if is_dir_linked "$src" "$dst"; then
    remove_dir_link "$dst"
    echo "  removed $name"
    restore_backup "$dst"
  else
    echo "  skip   $name (not managed by ai-dev-flow)"
  fi
}

echo "agents:"
if [ "$PLATFORM" = windows ]; then
  unlink_dir "$AGENTS_RENDERED_DIR" "$CLAUDE_DIR/agents"
else
  for f in "$REPO_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    unlink_file "$AGENTS_RENDERED_DIR/$name" "$CLAUDE_DIR/agents/$name"
  done
fi
rm -rf "$AGENTS_RENDERED_DIR"

echo ""
echo "commands:"
if [ "$PLATFORM" = windows ]; then
  unlink_dir "$REPO_DIR/commands" "$CLAUDE_DIR/commands"
else
  for f in "$REPO_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    unlink_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
  done
fi

echo ""
echo "skills:"
for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  unlink_dir "${d%/}" "$CLAUDE_DIR/skills/$(basename "$d")"
done

echo ""
echo "CLAUDE.md:"
unlink_file "$CLAUDE_MD_RENDERED" "$CLAUDE_DIR/CLAUDE.md"
rm -f "$CLAUDE_MD_RENDERED"

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
