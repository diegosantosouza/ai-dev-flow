# AI Dev Flow

A structured development methodology for building software with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It provides specialized AI agents, slash commands, and a battle-tested workflow that enforces **Research → Plan → Implement** on every feature.

Inspired by practices documented by [Fabio Akita](https://www.youtube.com/watch?v=W1GJjBk4HR0) and Anthropic's [Context Engineering](https://www.anthropic.com/engineering/claude-code-best-practices) principles.

## Why This Exists

Working with AI assistants on real codebases introduces common failure modes:

- **Context overload** — the conversation fills up with verbose test output and file contents, degrading response quality.
- **Brute-force solutions** — the AI jumps straight to implementation without researching established patterns or libraries.
- **No human checkpoint** — architectural decisions get made without review.
- **Inconsistent quality** — no systematic testing or code review step.

AI Dev Flow solves these by splitting work across **7 specialized agents** with isolated contexts, enforcing human approval at every critical decision point, and keeping the main conversation lean (40-60% of the context window).

## How It Works

Every non-trivial task follows three phases:

```
┌─────────────────────────────────────────────────────────┐
│                    /research                            │
│  researcher agent maps the codebase                    │
│  → human reviews findings                              │
├─────────────────────────────────────────────────────────┤
│                    /plan                                │
│  architect agent researches solutions (web + docs)     │
│  → detailed implementation plan                        │
│  → human approves before any code is written           │
├─────────────────────────────────────────────────────────┤
│                    /implement                           │
│  phase-by-phase execution                              │
│  → test-runner validates after each phase              │
│  → code-reviewer checks quality at the end             │
│  → /commit when done                                   │
└─────────────────────────────────────────────────────────┘
```

The key insight: **verbose work happens in subagents** (research, tests, reviews), so the main conversation stays focused and high-quality.

## Agents

| Agent | Model | Effort | Purpose |
|-------|-------|--------|---------|
| `architect` | opus | high | Researches algorithms, libraries, and design patterns before implementation |
| `code-reviewer` | sonnet | medium | Reviews code for quality, security, and best practices |
| `debugger` | sonnet | high | Diagnoses bugs and finds root causes |
| `researcher` | haiku | low | Maps codebase structure, files, patterns, and dependencies |
| `test-runner` | haiku | low | Runs tests and reports concise results |
| `doc-writer` | haiku | low | Creates and updates documentation |
| `committer` | haiku | low | Creates properly formatted git commits |

Agents with persistent memory (`researcher`, `architect`, `code-reviewer`) accumulate knowledge across sessions, getting better at understanding your codebase over time.

Each agent has an **effort level** (high/medium/low) that controls reasoning depth, and a **maxTurns** limit that prevents runaway sessions. High-effort agents think longer before responding; low-effort agents prioritize speed.

## Cost Optimization

Model selection is intentional, not arbitrary:

- **opus** for `architect` — architectural decisions are expensive to undo; the cost of a better model is negligible compared to the cost of rebuilding on the wrong foundation.
- **sonnet** for `code-reviewer` and `debugger` — analytical work that benefits from strong reasoning without needing the full weight of opus.
- **haiku** for `researcher`, `test-runner`, `doc-writer`, `committer` — mechanical tasks where speed matters more than depth.
- **Main session uses `opusplan`** — Opus during `/plan` (decisions matter most here), Sonnet during `/implement` (execution is more mechanical).

## Workflow Cost per Phase

| Phase | Agent | Model tier |
|-------|-------|------------|
| `/research` | `researcher` | haiku (fast, cheap) |
| `/plan` | `architect` | opus (expensive, worth it) |
| `/implement` | main session | sonnet via `opusplan` (balanced) |
| `/review` | `code-reviewer` | sonnet (balanced) |
| `/commit` | `committer` | haiku (trivial) |

## Commands

| Command | What it does |
|---------|-------------|
| `/research <topic>` | Delegates to `researcher` — understand the codebase before acting |
| `/plan <feature>` | Delegates to `architect` → enters plan mode for approval |
| `/implement` | Executes the approved plan phase by phase |
| `/review` | Delegates to `code-reviewer` — review recent changes |
| `/commit` | Delegates to `committer` — create a conventional commit |

## Installation

```bash
git clone https://github.com/gandarfh/ai-dev-flow.git
cd ai-dev-flow
chmod +x install.sh uninstall.sh
./install.sh
```

This symlinks agents, commands, and the global `CLAUDE.md` into `~/.claude/`. Existing files are backed up as `.bak`.

To remove:

```bash
./uninstall.sh
```

## Setting Up a New Project

Copy the template into your project root and customize it:

```bash
cp path/to/ai-dev-flow/CLAUDE.md.template ./CLAUDE.md
```

Edit the file to define your stack, conventions, testing rules, and current focus. Claude Code reads this file automatically when you open the project.

## Day-to-Day Impact

### Before AI Dev Flow

```
User: "Add authentication to the API"
AI: *immediately writes 500 lines of code*
    *picks a random approach*
    *no tests*
    *context window is now full of noise*
```

### After AI Dev Flow

```
User: /research authentication patterns in this codebase
  → researcher (haiku, low effort) maps existing auth code, middleware, models
  → human reviews: "we already have JWT utils in src/lib/"

User: /plan add OAuth2 login with Google
  → architect (opus, high effort) researches: passport.js vs arctic vs custom
  → presents trade-offs with documentation links
  → creates phased plan → human approves

User: /implement
  → main session switches to sonnet (opusplan)
  → Phase 1: Add OAuth routes → test-runner (haiku) validates ✓
  → Phase 2: Token exchange logic → test-runner validates ✓
  → Phase 3: Session management → test-runner validates ✓
  → code-reviewer (sonnet, medium effort) checks quality ✓

User: /commit
  → committer (haiku, low effort) creates:
  → feat(auth): add Google OAuth2 login flow
```

### What Changes in Practice

- **No wasted effort.** Research and planning happen before any code is written. You catch wrong approaches early.
- **Context stays clean.** Test output, file searches, and review checklists stay in subagents. Your main conversation remains useful for the full session.
- **Human stays in control.** You review research findings, approve plans, and decide when to commit. The AI proposes, you approve.
- **Consistent quality.** Every feature gets tested after each phase and reviewed before merging. This isn't optional — it's built into the workflow.
- **Knowledge compounds.** Agents with persistent memory learn your codebase conventions, preferred libraries, and patterns. They get better over time.
- **One session = one feature.** Context engineering keeps things focused. Start a new session for a new task.

## Architecture

```
~/.claude/
├── CLAUDE.md                  # Global instructions (auto-loaded)
├── agents/
│   ├── researcher.md          # Codebase mapper
│   ├── architect.md           # Solution researcher
│   ├── test-runner.md         # Test executor
│   ├── code-reviewer.md       # Quality checker
│   ├── debugger.md            # Bug diagnostician
│   ├── doc-writer.md          # Documentation writer
│   └── committer.md           # Git commit handler
└── commands/
    ├── research.md            # /research
    ├── plan.md                # /plan
    ├── implement.md           # /implement
    ├── review.md              # /review
    └── commit.md              # /commit
```

Each agent is a Markdown file with YAML frontmatter that defines its model, tools, permissions, and system prompt. Commands are thin wrappers that delegate to the right agent.

## Core Principles

1. **Research before you build.** Always understand the problem space and existing code before writing new code.
2. **Plan before you code.** Get human approval on the approach. Catch misunderstandings before they become bugs.
3. **Test after every phase.** Not at the end — after each phase. Failures are caught early and stay small.
4. **Keep context lean.** Delegate verbose work to subagents. Quality of AI output degrades with context noise.
5. **Never brute-force.** The `architect` agent must be consulted before implementing non-trivial features. There's usually an established pattern or library for the problem.

## License

MIT
