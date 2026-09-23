---
name: security-audit
description: Threat-model and audit a codebase, commit range, service, or PR for exploitable vulnerabilities, tenant-data exposure, auth bypass, injection, secrets leakage, and supply-chain/CI compromise. Use for dedicated security reviews, a pre-promotion gate to produção, or whenever asked to verify that a service protects users and tenant data.
argument-hint: <service name | path | commit range | PR#>
context: fork
agent: security-auditor
background: false
---

# Security Audit

Full invocation as typed: **$ARGUMENTS**

That's the scope to audit — a service name, a path, a commit range (`base..head`), or a PR
number. If it's ambiguous or missing, ask which scope before starting; don't default to
"the whole repo" silently, since that changes how long the audit takes.

Run your Preflight (scope + threat model), then apply your audit protocol to it.

## Steps

1. Phase 0: pin the exact scope and threat model — report this first, always.
2. Phase 1-2: static surface inventory — run the bundled scanner first:
   ```bash
   bash "${CLAUDE_SKILL_DIR}/scripts/security-surface.sh" <scope path>
   ```
   Then gather automated evidence from tools already configured in the project.
3. Phase 3: manual boundary audit using your checklist, reading only the ecosystem sections
   that apply (check for `package.json`/`go.mod`/`Dockerfile`/`k8s`/`.github/workflows` in the
   target before deciding which sections apply).
4. Phase 4-5: design adversarial tests, then verify every candidate finding yourself before it
   becomes a reported finding.
5. Phase 6: report using your standard output format. Do not edit anything — this skill is
   read-only.

## Output

Follow your standard output format exactly. Add one line at the end: if this audit was run as
a pre-promotion check (e.g. before a `housi-ship` PR to produção), state plainly whether any
`Critical`/`High` finding should block the promotion — that decision is the user's, but flag it
explicitly rather than burying it in the findings list.
