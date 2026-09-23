---
description: Research a solution with the architect, then enter plan mode for approval.
argument-hint: <feature>
---

Delegate to the `architect` subagent first: research established patterns, algorithms, and libraries for $ARGUMENTS

After the architect returns, apply the `verification-planning` skill to build an evidence path for this change proportionate to its risk — what needs to be proven, and how (unit tests, a live call in sandbox/homolog, `/obs-rca`/`/obs-gap`, `/k8s` inspection). A trivial change can rely on the project's ordinary tests; skip the full walkthrough for those.

Then use EnterPlanMode to create an implementation plan based on the architect's recommendation, including the plan's "Evidence path" section from verification-planning. Wait for approval before implementing.
