#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

echo "ai-dev-flow installer"
echo "repo:   $REPO_DIR"
echo "target: $CLAUDE_DIR"
echo ""

# --- dependencies check ---

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo "error: '$1' is required but not installed."
    echo "  install with: $2"
    exit 1
  fi
}

check_dependency jq "brew install jq"

# --- directories ---

mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands" "$CLAUDE_DIR/skills"

# --- helpers ---

link_file() {
  local src="$1"
  local dst="$2"
  local name
  name="$(basename "$src")"

  if [ -L "$dst" ]; then
    local current
    current="$(readlink "$dst")"
    if [ "$current" = "$src" ]; then
      echo "  skip  $name (already linked)"
      return
    fi
    echo "  update $name (relink)"
    rm "$dst"
  elif [ -f "$dst" ]; then
    echo "  backup $name -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
  else
    echo "  link  $name"
  fi

  ln -s "$src" "$dst"
}

# --- CLAUDE.md (render path placeholder) ---

CLAUDE_MD_SRC="$REPO_DIR/CLAUDE.md"
CLAUDE_MD_RENDERED="$REPO_DIR/.CLAUDE.md.rendered"

sed "s|~/gandarfh/ai-dev-flow|$REPO_DIR|g" "$CLAUDE_MD_SRC" > "$CLAUDE_MD_RENDERED"

# --- symlink agents ---

echo "agents:"
for f in "$REPO_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  link_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
done

# --- symlink commands ---

echo ""
echo "commands:"
for f in "$REPO_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  link_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
done

# --- symlink skills (whole directory per skill) ---

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
      echo "  skip  $name (already linked)"
    else
      echo "  update $name (relink)"
      rm "$dst"
      ln -s "$src" "$dst"
    fi
  elif [ -d "$dst" ]; then
    echo "  backup $name -> ${dst}.bak"
    mv "$dst" "${dst}.bak"
    ln -s "$src" "$dst"
  else
    echo "  link  $name"
    ln -s "$src" "$dst"
  fi
done

# --- CLAUDE.md ---

echo ""
echo "CLAUDE.md:"
link_file "$CLAUDE_MD_RENDERED" "$CLAUDE_DIR/CLAUDE.md"

# --- settings.json (model configuration) ---

echo ""
echo "settings:"

if [ ! -f "$SETTINGS_FILE" ]; then
  echo '{}' > "$SETTINGS_FILE"
  echo "  create settings.json"
fi

CURRENT_MODEL=$(jq -r '.model // empty' "$SETTINGS_FILE")

if [ "$CURRENT_MODEL" = "opusplan" ]; then
  echo "  skip  model (already set to opusplan)"
else
  if [ -n "$CURRENT_MODEL" ]; then
    echo "  update model ($CURRENT_MODEL -> opusplan)"
  else
    echo "  set   model -> opusplan"
  fi
  jq '.model = "opusplan"' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
fi

# --- validation ---

echo ""
echo "validating..."

ERRORS=0

# check symlinks
for f in "$REPO_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  target="$CLAUDE_DIR/agents/$name"
  if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$f" ]; then
    echo "  FAIL  agents/$name symlink broken"
    ERRORS=$((ERRORS + 1))
  fi
done

for f in "$REPO_DIR"/commands/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  target="$CLAUDE_DIR/commands/$name"
  if [ ! -L "$target" ] || [ "$(readlink "$target")" != "$f" ]; then
    echo "  FAIL  commands/$name symlink broken"
    ERRORS=$((ERRORS + 1))
  fi
done

if [ ! -L "$CLAUDE_DIR/CLAUDE.md" ] || [ "$(readlink "$CLAUDE_DIR/CLAUDE.md")" != "$CLAUDE_MD_RENDERED" ]; then
  echo "  FAIL  CLAUDE.md symlink broken"
  ERRORS=$((ERRORS + 1))
fi

# check settings.json model
FINAL_MODEL=$(jq -r '.model // empty' "$SETTINGS_FILE")
if [ "$FINAL_MODEL" != "opusplan" ]; then
  echo "  FAIL  settings.json model is '$FINAL_MODEL' (expected 'opusplan')"
  ERRORS=$((ERRORS + 1))
fi

# check agent frontmatter integrity
if ! bash "$REPO_DIR/scripts/validate-agents.sh" "$REPO_DIR/agents"; then
  ERRORS=$((ERRORS + 1))
fi

# check skill symlinks
for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  src="${d%/}"
  dst="$CLAUDE_DIR/skills/$name"
  if [ ! -L "$dst" ] || [ "$(readlink "$dst")" != "$src" ]; then
    echo "  FAIL  skills/$name symlink broken"
    ERRORS=$((ERRORS + 1))
  fi
done

# install pre-commit hook
echo ""
echo "hooks:"
HOOK_SOURCE="$REPO_DIR/scripts/pre-commit.sh"
HOOK_TARGET="$REPO_DIR/.git/hooks/pre-commit"
if [ -d "$REPO_DIR/.git/hooks" ]; then
  chmod +x "$HOOK_SOURCE"
  link_file "$HOOK_SOURCE" "$HOOK_TARGET"
else
  echo "  skip  pre-commit hook (no .git/hooks directory)"
fi

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s) found. Review the output above."
  exit 1
fi

echo "  OK    all checks passed"
echo ""
echo "done. restart claude code to pick up changes."
