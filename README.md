# AI Dev Flow

A structured development methodology for building software with [Claude Code](https://docs.anthropic.com/en/docs/claude-code). It provides specialized AI agents, slash commands, and a battle-tested workflow that enforces **Research → Plan → Implement** on every feature.

Inspired by practices documented by [Fabio Akita](https://www.youtube.com/watch?v=W1GJjBk4HR0) and Anthropic's [Context Engineering](https://www.anthropic.com/engineering/claude-code-best-practices) principles.

## Why This Exists

Working with AI assistants on real codebases introduces common failure modes:

- **Context overload** — the conversation fills up with verbose test output and file contents, degrading response quality.
- **Brute-force solutions** — the AI jumps straight to implementation without researching established patterns or libraries.
- **No human checkpoint** — architectural decisions get made without review.
- **Inconsistent quality** — no systematic testing or code review step.

AI Dev Flow solves these by splitting work across **9 specialized agents** with isolated contexts, enforcing human approval at every critical decision point, and keeping the main conversation lean (40-60% of the context window).

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
| `observability-analyst` | sonnet | high | Read-only. Correlates Grafana logs/metrics/traces with local code for root-cause analysis and instrumentation-gap audits. Requires the Grafana MCP server. |
| `observability-builder` | sonnet | high | Writes local files only. Generates Grafana dashboard panels and alert rules under `deploy/grafana/`, never writing to Grafana directly. |

Agents with persistent memory (`researcher`, `architect`, `code-reviewer`, `observability-analyst`) accumulate knowledge across sessions, getting better at understanding your codebase over time.

Each agent has an **effort level** (high/medium/low) that controls reasoning depth, and a **maxTurns** limit that prevents runaway sessions. High-effort agents think longer before responding; low-effort agents prioritize speed.

## Cost Optimization

Model selection is intentional, not arbitrary:

- **opus** for `architect` — architectural decisions are expensive to undo; the cost of a better model is negligible compared to the cost of rebuilding on the wrong foundation.
- **sonnet** for `code-reviewer` and `debugger` — analytical work that benefits from strong reasoning without needing the full weight of opus.
- **haiku** for `researcher`, `test-runner`, `doc-writer`, `committer` — mechanical tasks where speed matters more than depth.
- **Main session uses `opusplan`** — Opus during `/plan` (decisions matter most here), Sonnet during `/implement` (execution is more mechanical).
- **fable** — the highest tier available; intentionally **not** assigned to any default agent. Reserve it for frontier problems that genuinely exceed opus. Most work never needs it.

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

## Skills

Skills are reusable playbooks installed globally at `~/.claude/skills/`. Unlike commands, skills carry their own templates, scripts, and reference files — not just instructions.

| Skill | What it does |
|-------|-------------|
| `/otel-bootstrap <service-name>` | Bootstraps OpenTelemetry observability (tracer, metrics, Grafana dashboards, alert rules) into a Node.js or Go microservice. Auto-detects HTTP, PubSub, and cron components. |
| `/clean-orders <input.json> <barcodes.json> [output.json]` | Removes products from an orders JSON file whose barcode/EAN appears in a blocklist. Auto-detects the barcode field (`barcode`/`ean`/`gtin`/`sku`) and the products array (`products`/`items`/`lineItems`). Orders that become empty are dropped from the output. |
| `/obs-rca <error \| trace-id \| time window>` | Delegates to `observability-analyst` — correlates Grafana logs/traces with local code to find where a failure originated. |
| `/obs-gap <service-name>` | Delegates to `observability-analyst` — compares metrics instrumented in code against what actually arrived in Prometheus/Loki. |
| `/obs-panel <service-name> <what to visualize>` | Delegates to `observability-builder` — generates a new dashboard panel as a file under `deploy/grafana/dashboards/`. |
| `/obs-alert <service-name> <condition>` | Delegates to `observability-builder` — generates a new alert rule as a file under `deploy/grafana/alerts/`, with a threshold derived from real metric history. Direct invocation only (`disable-model-invocation: true`). |
| `/obs-apply <file...> [--apply]` | Applies dashboard/alert files to a real Grafana instance. Dry-run by default. Direct invocation only. |

See individual READMEs for full usage:
- [`skills/otel-bootstrap/README.md`](skills/otel-bootstrap/README.md)
- [`skills/clean-orders/README.md`](skills/clean-orders/README.md)
- [`skills/obs-rca/README.md`](skills/obs-rca/README.md)
- [`skills/obs-gap/README.md`](skills/obs-gap/README.md)
- [`skills/obs-panel/README.md`](skills/obs-panel/README.md)
- [`skills/obs-alert/README.md`](skills/obs-alert/README.md)
- [`skills/obs-apply/README.md`](skills/obs-apply/README.md)

### Security: the Grafana write path

`observability-analyst` and `observability-builder` never hold write access — their MCP server runs with `--disable-write` and their service account should be **Viewer only**. The only component that writes to Grafana is `scripts/apply.sh`, invoked exclusively through `/obs-apply`, authenticated with a **separate** `GRAFANA_ADMIN_TOKEN`. This keeps the blast radius of a misbehaving agent (or a prompt injection via log content) limited to proposing files — a human always reviews and explicitly runs `/obs-apply --apply`.

## Installation

```bash
git clone https://github.com/gandarfh/ai-dev-flow.git
cd ai-dev-flow
chmod +x install.sh uninstall.sh
./install.sh
```

This symlinks agents, commands, and the global `CLAUDE.md` into `~/.claude/`. Existing files are backed up as `.bak`.

> **Optional — Context7 MCP.** The `architect` agent lists Context7 tools (`mcp__plugin_context7_context7__*`) to query library docs. These only work if [Context7](https://github.com/upstash/context7) is configured as an MCP server in your environment. Without it, those tools silently no-op and the architect falls back to `WebSearch`/`WebFetch` — everything still works, just without live library-doc lookups. See the [subagent MCP docs](https://code.claude.com/docs/en/sub-agents).

> **Required for `observability-analyst`/`observability-builder` — Grafana MCP.** These two agents point at `scripts/mcp-grafana-env.sh`, a wrapper that loads this repo's **`.env`** and then execs [`mcp-grafana`](https://github.com/grafana/mcp-grafana) with `--disable-write`. This exists because MCP server config can only expand `${VAR}` from variables already exported in the shell that launched `claude` — there's no native way to point it at a project's `.env` file, so the wrapper bridges that gap. `install.sh` renders the wrapper's absolute path into the agent files at install time (same mechanism as the `CLAUDE.md` path substitution below), so this works regardless of where you cloned the repo. To use `/obs-rca`, `/obs-gap`, `/obs-panel`, or `/obs-alert` in a project:
> 1. Install `mcp-grafana` ([releases](https://github.com/grafana/mcp-grafana/releases) or `docker pull grafana/mcp-grafana`) and make sure the binary is on `PATH`.
> 2. Create a Grafana **service account with the Viewer role** (never Editor/Admin for this token — the agents are read-only by design; see [Security](#security-the-grafana-write-path)).
> 3. `cp .env.example .env` in this repo and fill in `GRAFANA_URL` and `GRAFANA_SERVICE_ACCOUNT_TOKEN`. `.env` is gitignored — never commit it. A value already exported in your shell still works as a fallback for anything you leave blank in `.env`.
> 4. If you also want trace-level root-cause analysis, enable `query_frontend.mcp_server.enabled: true` on your Tempo instance — without it, `/obs-rca` still works but falls back to logs + metrics only.
>
> Without these variables set (in `.env` or the shell), the Grafana tools fail to connect and the two agents report that in their Preflight step instead of guessing. `/obs-apply` reads `GRAFANA_URL` and `GRAFANA_ADMIN_TOKEN` (a separate, write-capable token) from the same `.env` — see [`skills/obs-apply/README.md`](skills/obs-apply/README.md).

To remove:

```bash
./uninstall.sh
```

## Configuration (`.env`)

As personalization grows (Grafana today, more integrations later), this repo centralizes external config in one file instead of requiring shell exports per project:

```bash
cp .env.example .env
# edit .env with real values
```

- **`.env.example`** — committed, documents every variable a skill or agent can consume.
- **`.env`** — gitignored, your real values. Read by `scripts/mcp-grafana-env.sh` (used by `observability-analyst`/`observability-builder`) and `skills/obs-apply/scripts/apply.sh`.
- A variable already exported in your shell still works if you leave it blank in `.env` — `.env` fills gaps and can override, but a blank line never clobbers a real shell value.
- Add new variables to `.env.example` (with a comment on what uses them) whenever a new skill/agent needs configuration, so `.env` stays the single place to look.

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
│   ├── committer.md           # Git commit handler
│   ├── observability-analyst.md  # Read-only Grafana + code correlation
│   └── observability-builder.md  # Writes dashboard/alert files
├── commands/
│   ├── research.md            # /research
│   ├── plan.md                # /plan
│   ├── implement.md           # /implement
│   ├── review.md              # /review
│   └── commit.md              # /commit
└── skills/
    ├── otel-bootstrap/        # /otel-bootstrap <service-name>
    │   ├── SKILL.md
    │   ├── templates/         # node/, go/, grafana/
    │   └── scripts/           # render.sh, detect.sh, validate.sh
    ├── clean-orders/          # /clean-orders <input> <barcodes> [output]
    │   ├── SKILL.md
    │   └── scripts/           # clean.js (zero deps)
    ├── obs-rca/                # /obs-rca <error|trace-id|window> — forks observability-analyst
    ├── obs-gap/                # /obs-gap <service-name> — forks observability-analyst
    ├── obs-panel/              # /obs-panel <service-name> <what> — forks observability-builder
    ├── obs-alert/              # /obs-alert <service-name> <condition> — forks observability-builder
    └── obs-apply/              # /obs-apply <file...> [--apply] — runs in main session
        └── scripts/            # apply.sh (jq + optional yq)
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
