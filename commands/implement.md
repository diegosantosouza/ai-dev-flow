---
description: Execute the approved plan phase by phase, testing after each phase.
argument-hint: [feature]
disable-model-invocation: true
---

Implement $ARGUMENTS following the approved plan (if any), phase by phase.

After each phase, delegate to the `test-runner` subagent to verify. If tests fail, fix before moving forward.

When finished, delegate to the `code-reviewer` subagent to review the changes.
