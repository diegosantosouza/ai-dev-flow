# Global Development Flow

## Workflow: Research → Plan → Implement

For any non-trivial task, follow the 3-phase cycle:

1. **Research**: Use the `researcher` subagent to map the codebase before acting. Human reviews before moving forward.
2. **Plan**: Use EnterPlanMode to create a detailed specification. Wait for approval.
3. **Implement**: Execute phase by phase. Use the `test-runner` subagent after each phase. Never implement everything at once.

## Available Subagents

- `architect` (opus, read-only, persistent memory, web access + context7) — research algorithms, patterns, libraries and architectures BEFORE implementing. Must be consulted before brute-forcing any solution.
- `researcher` (haiku, read-only, persistent memory) — research codebase structure, files, and conventions
- `test-runner` (haiku, read-only) — run tests and report concise results
- `code-reviewer` (sonnet, read-only, persistent memory) — review code after changes
- `debugger` (sonnet, read-only) — diagnose bugs, find root causes, recommend fixes
- `doc-writer` (haiku, can write) — create or update documentation
- `committer` (haiku, bypassPermissions) — create conventional git commits

Use them proactively to preserve context in the main conversation.

**IMPORTANT**: Before implementing any non-trivial feature, ALWAYS use the `architect` agent first to research if there's an established algorithm, pattern, or library for the problem. Never brute-force a solution.

## Context Engineering

- Keep context lean (40-60% of the window)
- Delegate research and tests to subagents (verbose output stays isolated)
- Compact results: summarize, preserve decisions, discard noise
- One session = one feature or fix

## Communication

- When making claims about how tools, frameworks, or features work, always back them up with a source (documentation link, official reference, or the specific file/line in the codebase).
- If you are not sure about something, say so explicitly — do not guess or present assumptions as facts.
- When corrected, acknowledge the mistake clearly before presenting the right information.

## General Rules

- All new code MUST have tests
- Run tests (via `test-runner`) before considering any task complete
- Do not add dependencies without confirming first
- Do not change architecture without prior discussion
- Solve the current problem, not hypothetical ones (no over-engineering)
- If no CLAUDE.md exists in the project, suggest creating one based on the template at ~/gandarfh/ai-dev-flow/CLAUDE.md.template
