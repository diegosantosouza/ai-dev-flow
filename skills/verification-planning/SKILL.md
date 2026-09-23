---
name: verification-planning
description: Build an evidence path before implementing non-trivial work — what needs to be proven, how this specific system can prove or refute it, and whether unit tests alone are enough. Use as part of /plan for any feature, bug fix, refactor, or cross-service change, especially when the real proof lives in runtime behavior (traces, metrics, logs, a live call in an environment) rather than in a unit test.
argument-hint: [feature or change being planned]
---

# Verification Planning

## Why this exists

A plan that only says "add tests" answers *whether the code runs*, not *whether the change
is actually true in production*. For microservices running across sandbox/homolog/produção,
the strongest evidence is frequently not a unit test at all — it is a trace in Tempo, a
metric in Grafana, a log line in Loki, or a real HTTP call against a running pod. This skill
builds that evidence path deliberately, as part of `/plan`, before any code is written.

Use it proportionately: a one-line fix can rely on the project's ordinary test suite.
Reserve the full walkthrough for changes where a wrong confident conclusion would be costly
— cross-service behavior, anything touching multiple environments, or anything whose only
prior evidence was "it compiled."

## 1. Frame the claim

State the exact behavior that needs to become true, and the conditions under which a
confident "it works" would actually be wrong. Consider: what must change, what must stay
true (an invariant, a downstream contract), where the behavior crosses a service or
environment boundary, and which failure mode would matter most if missed.

**Done when:** the claim and its most important failure modes are concrete enough to
investigate — not "the endpoint works" but "the endpoint returns the tenant's own orders
only, even under concurrent requests from two tenants."

## 2. Design the evidence path

List the possible routes to evidence for *this* claim, then pick one deliberately instead of
defaulting to "write a unit test." Typical Housi evidence sources, roughly cheapest first:

- **Unit/integration test** (`test-runner`) — cheapest, best for pure logic and contract
  boundaries inside one service.
- **Local reproduction** — reproduce the exact input/state that would trigger the failure
  mode, with synthetic data.
- **Live call in sandbox/homolog** (`/k8s-pf` to tunnel in, or a direct call once deployed) —
  needed when the claim depends on real infra (Keycloak tokens, GKE networking, a real DB).
- **Traces/metrics/logs** (`/obs-rca`, `/obs-gap`) — needed when the claim is about behavior
  under real traffic, timing, or an interaction between services that a unit test can't see.
- **`/k8s` inspection** (pod state, logs, `describe`) — needed when the claim is about
  deployment/runtime behavior, not application logic.

Never treat production as a place to gather first evidence — sandbox/homolog first, and only
touch produção with the same confirmation discipline `k8s` and `housi-ship` already require.

Generate at least one alternative before settling on a path. Prefer the option that gives a
trustworthy conclusion for proportionate cost and safety over the option that is merely
familiar.

**Done when:** there's a preferred path, its limitations are stated, and a fallback exists if
it turns out to be insufficient.

## 3. Set a verification budget

List the distinct claims from step 1, and for each one pick the minimum non-duplicative
evidence that covers it. Don't re-run an expensive check (a full homolog smoke test, a
cross-service trace query) for every small iteration — reuse it only while the code, inputs,
and environment it covered remain unchanged. The project's required gates
(`test-runner`, lint/build) still run regardless; this budget is about what to add on top.

## 4. Create a verification affordance only when needed

If the existing system leaves the claim too indirect to observe — no metric, no log line, no
way to reproduce the state — consider adding the smallest capability that makes it
observable: a debug log, a temporary metric, a script that seeds the exact state. Decide
explicitly whether it's temporary (remove after this change ships) or durable (worth keeping,
e.g. a metric `/obs-panel` should also visualize going forward).

Ask before adding a new dependency or a persistent diagnostic surface purely to gather this
evidence — that's a real decision, not a free side effect.

**Done when:** the chosen path can establish the claim directly enough for what's at stake,
and any new affordance has a stated lifecycle (temporary vs. durable).

## 5. Research when the path is unfamiliar

If the right evidence path depends on an unfamiliar library, framework, or external service
(a Keycloak flow, a GCP networking behavior, an OTel exporter quirk), delegate a focused
question to the `architect` subagent before committing to an approach, rather than guessing.

## 6. Close the evidence path

After implementation, follow the path exactly as planned and report the result against the
original claim from step 1:

- **Established** — the evidence confirms the claim.
- **Limited** — the evidence is consistent with the claim but doesn't rule out every failure
  mode named in step 1 (say which one is still open).
- **Refuted** — the evidence contradicts the claim; go back to root cause, don't patch around
  the observation.

State this explicitly in the plan/implementation summary so a future reader can see what
actually supports "this works," not just that tests were green.

## Output (add this section to the plan produced by `/plan`)

```markdown
### Evidence path
- Claim: <the exact behavior being proven>
- Path: <test-runner | k8s-pf live call | obs-rca/obs-gap | k8s inspection | combination>
- Why this path: <what it can prove that a unit test alone can't, or why a unit test is enough>
- Affordance added (if any): <what, and temporary/durable>
- Verification budget: <what runs once vs. what reruns each iteration>
```

After `/implement`, close it out:

```markdown
### Evidence path result
- Established | Limited (open: <what>) | Refuted (root cause: <what>)
```
