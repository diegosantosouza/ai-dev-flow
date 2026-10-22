#!/usr/bin/env bash
# Lint for the /pipe skills (skills/pipe*) and agents (agents/pipe-*).
# Usage: validate-pipe.sh [repo-root]
# Exit 0 if all pass, exit 1 if any fail.
#
# Claude Code silently ignores an unknown frontmatter field, so a typo (disallowed-tools vs
# disallowedTools) never shows up at runtime. These checks catch it, plus the structural rules the
# /pipe chain depends on:
#   S1  frontmatter keys are in the allowlist (all skills and agents)
#   S2  invocation flags: pipe is human-only, the stages are model-only, none forks or sets a model
#   S3  no leftover wording from the old engine, every pipe agent has maxTurns, tool limits per role
#   S4  every pipe-<x> named in a pipe skill or agent exists as a skill or an agent
#   S5  each pipe skill is at most 16000 bytes (compaction re-attaches a skill only up to a limit)
#   S6  the builder, the validator and the reviewer call /usr/bin/git and /usr/bin/grep, never the bare commands
#   S7  no bare `cd <path>` in the skills (a subshell or an absolute path instead)
# Sources: https://code.claude.com/docs/en/skills , https://code.claude.com/docs/en/sub-agents
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
SKILLS_DIR="$ROOT/skills"
AGENTS_DIR="$ROOT/agents"

ERRORS=0
fail() { echo "  FAIL  $1"; ERRORS=$((ERRORS + 1)); }

SKILL_KEYS=" name description when_to_use argument-hint arguments disable-model-invocation user-invocable allowed-tools disallowed-tools model effort context agent background hooks paths shell metadata license compatibility "
AGENT_KEYS=" name description tools disallowedTools model permissionMode mcpServers hooks maxTurns autoCompactWindow skills initialPrompt memory effort background omitClaudeMd isolation color experimental "

# frontmatter <file>  -> the lines between the first two '---'
frontmatter() { awk 'NR==1 && $0!="---" {exit} NR>1 && $0=="---" {exit} NR>1 {print}' "$1"; }
# keys <file>  -> top-level keys of the frontmatter (indented lines belong to a nested block)
keys() { frontmatter "$1" | sed -n 's/^\([A-Za-z][A-Za-z_-]*\):.*/\1/p'; }
# field <file> <key>  -> the value of a top-level key, trimmed
field() { frontmatter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]*$//'; }
has_key() { keys "$1" | grep -qx "$2"; }
body() { awk 'BEGIN{n=0} n>=2 {print} $0=="---" {n++}' "$1"; }

# --- S1: allowlist, over every skill and agent --------------------------------------------------

for f in "$SKILLS_DIR"/*/SKILL.md; do
  [ -f "$f" ] || continue
  name="$(basename "$(dirname "$f")")"
  for k in $(keys "$f"); do
    case "$SKILL_KEYS" in *" $k "*) ;; *) fail "S1 skills/$name: unknown frontmatter field '$k'" ;; esac
  done
done
for f in "$AGENTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  name="$(basename "$f")"
  for k in $(keys "$f"); do
    case "$AGENT_KEYS" in *" $k "*) ;; *) fail "S1 agents/$name: unknown frontmatter field '$k'" ;; esac
  done
done

# --- S2: invocation flags -----------------------------------------------------------------------

PIPE_SKILLS=""
for d in "$SKILLS_DIR"/pipe "$SKILLS_DIR"/pipe-*; do
  [ -f "$d/SKILL.md" ] && PIPE_SKILLS="$PIPE_SKILLS $(basename "$d")"
done
PIPE_AGENTS=""
for f in "$AGENTS_DIR"/pipe-*.md; do
  [ -f "$f" ] && PIPE_AGENTS="$PIPE_AGENTS $(basename "$f" .md)"
done

for s in $PIPE_SKILLS; do
  f="$SKILLS_DIR/$s/SKILL.md"
  has_key "$f" context && fail "S2 skills/$s: 'context' is set (the stages ask the human, and a fork has no AskUserQuestion)"
  has_key "$f" agent && fail "S2 skills/$s: 'agent' is set"
  has_key "$f" model && fail "S2 skills/$s: 'model' is set (the model comes from the dispatched agent)"
  if [ "$s" = pipe ]; then
    [ "$(field "$f" disable-model-invocation)" = true ] || fail "S2 skills/pipe: disable-model-invocation must be true"
    has_key "$f" hooks || fail "S2 skills/pipe: missing the hooks block"
  else
    [ "$(field "$f" user-invocable)" = false ] || fail "S2 skills/$s: user-invocable must be false"
    has_key "$f" disable-model-invocation && fail "S2 skills/$s: disable-model-invocation would block the chain"
  fi
done
for need in pipe pipe-spec pipe-build pipe-verify; do
  case " $PIPE_SKILLS " in *" $need "*) ;; *) fail "S2 skills/$need is missing" ;; esac
done

# --- S3: engine leftovers, maxTurns, tool limits ------------------------------------------------

LEFTOVERS='native close|pipeline check|native-hooks|única instrução com autoridade|--exit|node <CLI>|workflow-ia|PROGRESS\.md|verdict-<token>|slice/<'
# The entry skill may name the old runtime: `adopt` reads its missions and the preflight spots its hooks.
ENTRY_LEFTOVERS='native close|pipeline check|única instrução com autoridade|--exit|node <CLI>|PROGRESS\.md|verdict-<token>|slice/<'
for s in $PIPE_SKILLS; do
  pat="$LEFTOVERS"
  [ "$s" = pipe ] && pat="$ENTRY_LEFTOVERS"
  if grep -n -E "$pat" "$SKILLS_DIR/$s/SKILL.md" >/dev/null; then
    fail "S3 skills/$s: mentions the old engine ($(grep -o -E "$pat" "$SKILLS_DIR/$s/SKILL.md" | sort -u | tr '\n' ' '))"
  fi
done
for a in $PIPE_AGENTS; do
  f="$AGENTS_DIR/$a.md"
  if grep -n -E "$LEFTOVERS" "$f" >/dev/null; then
    fail "S3 agents/$a: mentions the old engine ($(grep -o -E "$LEFTOVERS" "$f" | sort -u | tr '\n' ' '))"
  fi
  has_key "$f" maxTurns || fail "S3 agents/$a: missing maxTurns"
done
if [ -f "$AGENTS_DIR/pipe-builder.md" ]; then
  [ "$(field "$AGENTS_DIR/pipe-builder.md" isolation)" = worktree ] || fail "S3 agents/pipe-builder: isolation must be worktree"
fi
if [ -f "$AGENTS_DIR/pipe-validator.md" ]; then
  field "$AGENTS_DIR/pipe-validator.md" disallowedTools | grep -q 'Edit' || fail "S3 agents/pipe-validator: disallowedTools must include Edit"
fi
if [ -f "$AGENTS_DIR/pipe-reviewer.md" ]; then
  v="$(field "$AGENTS_DIR/pipe-reviewer.md" disallowedTools)"
  echo "$v" | grep -q 'Edit' && echo "$v" | grep -q 'Write' || fail "S3 agents/pipe-reviewer: disallowedTools must include Write and Edit"
fi
if [ -f "$AGENTS_DIR/pipe-reproducer.md" ]; then
  fail "S3 agents/pipe-reproducer.md must not exist (the builder absorbs kind: bug)"
fi

# --- S4: every pipe-<x> named exists ------------------------------------------------------------

NAMED="$( { for s in $PIPE_SKILLS; do body "$SKILLS_DIR/$s/SKILL.md"; done; for a in $PIPE_AGENTS; do body "$AGENTS_DIR/$a.md"; done; } | { grep -o -E 'pipe-[a-z]+' || true; } | sort -u)"
for n in $NAMED; do
  if [ ! -f "$SKILLS_DIR/$n/SKILL.md" ] && [ ! -f "$AGENTS_DIR/$n.md" ]; then
    fail "S4 '$n' is named but there is no skill or agent with that name"
  fi
done

# --- S5: size -----------------------------------------------------------------------------------

for s in $PIPE_SKILLS; do
  size="$(wc -c < "$SKILLS_DIR/$s/SKILL.md" | tr -d ' ')"
  [ "$size" -le 16000 ] || fail "S5 skills/$s: $size bytes (limit 16000)"
done

# --- S6: absolute git and grep in the independent verifiers --------------------------------------

for a in pipe-builder pipe-validator pipe-reviewer; do
  f="$AGENTS_DIR/$a.md"
  [ -f "$f" ] || continue
  if body "$f" | grep -n -E '(^|[^/A-Za-z-])git( -c [^ ]+)?( -C [^ ]+)? (diff|log|show|status|add|commit|stash|branch|fetch|pull|worktree|checkout|switch|restore)' >/dev/null; then
    fail "S6 agents/$a: bare git command (use /usr/bin/git: the global hook rewrites the short form and the worktree guard refuses it)"
  fi
  if body "$f" | grep -n -E '(^|[^/A-Za-z-])grep( |$)' >/dev/null; then
    fail "S6 agents/$a: bare 'grep' (use /usr/bin/grep)"
  fi
  body "$f" | grep -q '/usr/bin/git' || fail "S6 agents/$a: never mentions /usr/bin/git"
done

# --- S7: no bare cd in the skills ----------------------------------------------------------------
# The Bash tool keeps its directory between calls, and isolation: worktree needs the session inside the
# repo. A `cd <mission folder>` left behind makes the dispatch fail with "not in a git repository".

for s in $PIPE_SKILLS; do
  if body "$SKILLS_DIR/$s/SKILL.md" | sed -e 's/( *cd //g' | grep -n -E '(^|[^A-Za-z-])cd [~$/"'"'"']' >/dev/null; then
    fail "S7 skills/$s: bare 'cd <path>' (use a subshell: ( cd <path> && ... ), or an absolute path)"
  fi
done

if [ "$ERRORS" -gt 0 ]; then
  echo ""
  echo "FAILED: $ERRORS error(s) in the /pipe skills and agents. Fix before committing."
  exit 1
fi

echo "  OK    all /pipe lint checks passed"
