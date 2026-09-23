---
name: reflect
description: Review recent sessions and the current ai-dev-flow setup to find repeated workflow friction, then recommend the smallest useful fix — a CLAUDE.md rule, a prompt tweak on an existing agent, a new skill, a new agent, or no change at all. Use when asked to learn from past sessions, improve a recurring workflow, or find what should become reusable.
argument-hint: [focus area]
disable-model-invocation: true
---

# Reflect

Reflect looks back at how this methodology has actually been used and recommends the
smallest useful improvement. Run it directly (`/reflect` or `/reflect <focus>`) — it isn't
meant to fire on its own mid-task, since it's an introspective review of the setup itself,
not a step in a feature's Research → Plan → Implement cycle.

**"No change" is a valid, often correct outcome.** Don't manufacture a skill or agent to
justify having run this.

## 1. Inventory what already exists

Before proposing anything, know what's already there so you don't recommend a near-duplicate:

- `ai-dev-flow/agents/*.md`, `ai-dev-flow/commands/*.md`, `ai-dev-flow/skills/*/SKILL.md`
- `~/.claude/skills/` (anything installed outside this repo)
- Your own memory (agents with `memory: user` accumulate notes — check for prior reflect
  runs or relevant recorded patterns)

## 2. Gather evidence from real sessions

Session transcripts live as JSONL files under `~/.claude/projects/<project-dir>/*.jsonl`.
Delegate the raw extraction to the `researcher` subagent instead of reading transcripts
directly — they're large and full of tool-call noise that shouldn't fill this context.

Ask `researcher` for a **compact summary**, not raw content:
- The most recent N sessions (or since a given date if the user gave a focus/timeframe).
- Counts of repeated request shapes (the same kind of ask across sessions), repeated manual
  Bash command patterns, and repeated corrections the user gave.
- 1-2 short verbatim examples per repeated pattern (not full transcripts).

Never surface raw personal or sensitive content from a transcript in the final report or in
any generated asset — only the abstracted pattern and short, non-sensitive examples.

## 3. Score candidates

For each repeated pattern found, judge:

- **Frequency** — how many times has this actually happened?
- **Cost** — real time/context/attention wasted redoing it by hand?
- **Risk** — does doing it inconsistently by hand cause bugs or bad decisions?
- **Stability** — are the inputs and desired output predictable enough to codify?
- **Coverage** — is there already an asset (agent/skill/command/CLAUDE.md rule) that handles
  this, even partially?

A candidate needs at least two real occurrences with stable inputs and a clear output to be
worth acting on. One-off requests, however memorable, are not evidence of a pattern.

## 4. Pick the smallest useful form

In order of increasing weight — always prefer the lightest form that solves it:

1. **Nothing** — the friction is real but too rare, too ambiguous, or already handled.
2. **A CLAUDE.md rule** — a short standing instruction (like the ones added in this project's
   General Rules section).
3. **A prompt tweak on an existing agent** — add a rule/section to `agents/<name>.md` rather
   than create a new agent.
4. **A new skill** — a distinct, repeatable workflow shape with its own trigger.
5. **A new agent** — only when the work needs a genuinely distinct model/tools/effort profile
   that no existing agent covers (see the `/new-agent` command for scaffolding).

Skip a new agent when a prompt rule or skill would do. Skip a new skill when a CLAUDE.md rule
would do.

## 5. Propose before changing

Present findings and recommendations; do not write or edit anything until the user confirms
which recommendation(s) to apply:

```text
Findings
- <workflow>: <N> occurrences, evidence: <short example>. Recommended: <form>.

Recommended changes
- <file/asset>: one-line purpose and why this is the smallest useful form.

Skipped
- <candidate>: why it doesn't clear the bar yet.
```

If nothing clears the bar:

```text
No strong repeated pattern found. No change recommended.
```

## Guardrails

- Don't create overlapping skills/agents — check step 1 first.
- Don't change CLAUDE.md, an agent, or a skill without the user confirming which
  recommendation to apply.
- Don't overfit to a single session unless the user explicitly asks for that one workflow to
  become reusable regardless of frequency.
- After any change, note that it takes effect on the next Claude Code session/skill reload in
  this project (agents and skills load at session start).

Adapted from the `reflect` methodology in
[akitaonrails/my-skills](https://github.com/akitaonrails/my-skills), retargeted from
OpenCode's `.slim/` session logs to this project's transcripts and asset layout.
