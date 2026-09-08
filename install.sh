#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
SETTINGS_FILE="$CLAUDE_DIR/settings.json"

# shellcheck source=scripts/link-lib.sh
. "$REPO_DIR/scripts/link-lib.sh"

echo "ai-dev-flow installer"
echo "repo:     $REPO_DIR"
echo "target:   $CLAUDE_DIR"
echo "platform: $PLATFORM"
echo ""

# --- dependencies check ---

check_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo "error: '$1' is required but not installed."
    echo "  install with: $2"
    exit 1
  fi
}

check_optional_dependency() {
  if ! command -v "$1" &>/dev/null; then
    echo "note: '$1' is not installed ($3). Install with: $2"
  fi
}

pkg_hint() { # tool
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      case "$1" in
        jq) echo "winget install jqlang.jq" ;;
        yq) echo "winget install MikeFarah.yq" ;;
        *)  echo "winget install $1" ;;
      esac
      ;;
    Darwin) echo "brew install $1" ;;
    *)
      if   command -v apt-get &>/dev/null; then echo "sudo apt-get install $1"
      elif command -v dnf     &>/dev/null; then echo "sudo dnf install $1"
      elif command -v pacman  &>/dev/null; then echo "sudo pacman -S $1"
      elif command -v apk     &>/dev/null; then echo "sudo apk add $1"
      elif command -v zypper  &>/dev/null; then echo "sudo zypper install $1"
      else echo "your package manager"
      fi
      ;;
  esac
}

check_dependency jq "$(pkg_hint jq)"
check_optional_dependency yq "$(pkg_hint yq)" "only needed by /obs-apply to apply alert-rule YAML files"

link_lib_init

# --- link wrappers ----------------------------------------------------------

link_file() {
  local src="$1"
  local dst="$2"
  local name bak
  name="$(basename "$dst")"

  if is_file_linked "$src" "$dst"; then
    echo "  skip  $name (already linked)"
    return
  fi

  if [ -L "$dst" ]; then
    echo "  update $name (relink)"
    rm "$dst"
  elif [ -e "$dst" ] && cmp -s "$src" "$dst"; then
    # Same bytes as the source: a hardlink orphaned when something rewrote the source
    # (a `git pull` replaces a file rather than editing it in place). There is nothing
    # of the user's to preserve, so relink instead of piling up backups.
    echo "  update $name (relink)"
    rm "$dst"
  elif [ -e "$dst" ]; then
    bak="$(backup_path "$dst")"
    echo "  backup $name -> $(basename "$bak")"
    mv "$dst" "$bak"
  else
    echo "  link  $name"
  fi

  make_file_link "$src" "$dst"
}

link_dir() {
  local src="$1"
  local dst="$2"
  local name bak
  name="$(basename "$dst")"

  if is_dir_linked "$src" "$dst"; then
    echo "  skip  $name (already linked)"
    return
  fi

  if [ -L "$dst" ]; then
    echo "  update $name (relink)"
    remove_dir_link "$dst"
  elif [ -e "$dst" ]; then
    bak="$(backup_path "$dst")"
    echo "  backup $name -> $(basename "$bak")"
    mv "$dst" "$bak"
  else
    echo "  link  $name"
  fi

  make_dir_link "$src" "$dst"
}

# --- directories ---

mkdir -p "$CLAUDE_DIR/skills"

# On Windows agents/ and commands/ are linked as whole directories, so they must not be
# pre-created here or the junction would have nowhere to go.
if [ "$PLATFORM" = posix ]; then
  mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/commands"
fi

# --- render path -------------------------------------------------------------
# The substituted path is read back by Claude Code, a native Windows process there that
# does not understand a /c/... MSYS path.

if [ "$PLATFORM" = windows ]; then
  RENDER_PATH="$(cygpath -m "$REPO_DIR")"
else
  RENDER_PATH="$REPO_DIR"
fi

# --- CLAUDE.md (render path placeholder) ---

CLAUDE_MD_SRC="$REPO_DIR/CLAUDE.md"
CLAUDE_MD_RENDERED="$REPO_DIR/.CLAUDE.md.rendered"

sed "s|~/gandarfh/ai-dev-flow|$RENDER_PATH|g" "$CLAUDE_MD_SRC" > "$CLAUDE_MD_RENDERED"

# --- render + link agents (same path-placeholder substitution as CLAUDE.md, so an
#     agent's mcpServers.command can reference a script inside this repo by absolute path) ---

AGENTS_RENDERED_DIR="$REPO_DIR/.agents.rendered"
mkdir -p "$AGENTS_RENDERED_DIR"
chmod +x "$REPO_DIR/scripts/mcp-grafana-env.sh" 2>/dev/null || true

echo "agents:"
for f in "$REPO_DIR"/agents/*.md; do
  [ -f "$f" ] || continue
  sed "s|~/gandarfh/ai-dev-flow|$RENDER_PATH|g" "$f" > "$AGENTS_RENDERED_DIR/$(basename "$f")"
done

# A render outlives the agent it came from, and both link strategies below would happily
# publish that leftover as a live agent.
for r in "$AGENTS_RENDERED_DIR"/*.md; do
  [ -f "$r" ] || continue
  [ -f "$REPO_DIR/agents/$(basename "$r")" ] || rm "$r"
done

# Per-file links on Windows would have to be hardlinks, and `git pull` replaces a file
# rather than rewriting it in place, which orphans a hardlink without warning. Linking
# the directory keeps the install tracking the repo across pulls.
if [ "$PLATFORM" = windows ]; then
  link_dir "$AGENTS_RENDERED_DIR" "$CLAUDE_DIR/agents"
else
  for f in "$AGENTS_RENDERED_DIR"/*.md; do
    [ -f "$f" ] || continue
    link_file "$f" "$CLAUDE_DIR/agents/$(basename "$f")"
  done
fi

# --- link commands ---

echo ""
echo "commands:"
if [ "$PLATFORM" = windows ]; then
  link_dir "$REPO_DIR/commands" "$CLAUDE_DIR/commands"
else
  for f in "$REPO_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    link_file "$f" "$CLAUDE_DIR/commands/$(basename "$f")"
  done
fi

# --- link skills (whole directory per skill) ---

echo ""
echo "skills:"
for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  link_dir "${d%/}" "$CLAUDE_DIR/skills/$(basename "$d")"
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

fail() {
  echo "  FAIL  $1"
  ERRORS=$((ERRORS + 1))
}

if [ "$PLATFORM" = windows ]; then
  is_dir_linked "$AGENTS_RENDERED_DIR" "$CLAUDE_DIR/agents" || fail "agents/ junction broken"
  is_dir_linked "$REPO_DIR/commands" "$CLAUDE_DIR/commands" || fail "commands/ junction broken"

  for f in "$REPO_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    [ -f "$CLAUDE_DIR/agents/$(basename "$f")" ] || fail "agents/$(basename "$f") not reachable through the junction"
  done

  for f in "$REPO_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    [ -f "$CLAUDE_DIR/commands/$(basename "$f")" ] || fail "commands/$(basename "$f") not reachable through the junction"
  done
else
  for f in "$REPO_DIR"/agents/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    is_file_linked "$AGENTS_RENDERED_DIR/$name" "$CLAUDE_DIR/agents/$name" || fail "agents/$name symlink broken"
  done

  for f in "$REPO_DIR"/commands/*.md; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    is_file_linked "$f" "$CLAUDE_DIR/commands/$name" || fail "commands/$name symlink broken"
  done
fi

is_file_linked "$CLAUDE_MD_RENDERED" "$CLAUDE_DIR/CLAUDE.md" || fail "CLAUDE.md link broken"

# check settings.json model
FINAL_MODEL=$(jq -r '.model // empty' "$SETTINGS_FILE")
if [ "$FINAL_MODEL" != "opusplan" ]; then
  fail "settings.json model is '$FINAL_MODEL' (expected 'opusplan')"
fi

# check agent frontmatter integrity
if ! bash "$REPO_DIR/scripts/validate-agents.sh" "$REPO_DIR/agents"; then
  ERRORS=$((ERRORS + 1))
fi

# check skill frontmatter integrity
if ! bash "$REPO_DIR/scripts/validate-skills.sh" "$REPO_DIR/skills" "$REPO_DIR/agents"; then
  ERRORS=$((ERRORS + 1))
fi

# check skill links
for d in "$REPO_DIR"/skills/*/; do
  [ -d "$d" ] || continue
  name="$(basename "$d")"
  is_dir_linked "${d%/}" "$CLAUDE_DIR/skills/$name" || fail "skills/$name link broken"
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
