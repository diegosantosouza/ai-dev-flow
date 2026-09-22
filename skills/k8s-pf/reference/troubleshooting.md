# k8s-pf troubleshooting

Exit codes are stable — script and agent flows should branch on them, not on
message text.

| Exit | Meaning | What to do |
|---|---|---|
| 2 | Usage error / missing dependency | Fix the invocation; if `jq`/`yq`/`kubectl` is missing, install it (`pf.sh doctor` says which) |
| 3 | Unknown target — not in the catalog even after an auto-sync retry | Check the *did-you-mean* suggestion; try `pf.sh list` or `pf.sh sync --all` |
| 4 | Environment missing or ambiguous for this target | **Ask the user which environment** — never guess, sandbox included |
| 5 | Local port already in use by something else | The error names the PID/command holding it. Use `--local-port` to pick another, or `pf.sh down <id>` first if it's a stale tunnel of ours |
| 6 | No such open forward, or resource not found | Check the id with `pf.sh status`, or the target with `pf.sh list` |
| 7 | Service exists but has zero ready endpoints | The workload is scaled to 0 or unhealthy — check with the `k8s` skill (`kubectl get pods`), this isn't a port-forward problem |
| 8 | Auth/RBAC failure | `pf.sh doctor` shows whether `gcloud auth` is active; `Forbidden` means the identity lacks RBAC for that namespace/verb, not a stale token |
| 9 | The security guard (`housi-k8s-guard.sh`) denied confirmation | Relay the hook's message to the user as-is — this is the intended safety net, not a bug |
| 10 | Supervisor gave up (restart budget exhausted, or classified a fatal error) | Read `pf.sh logs <id>` — the last line names the reason |

## Why `up` never runs kubectl itself

`pf.sh up` resolves the target, allocates the port, writes the forward's
state directory, and **prints** the exact `kubectl ... port-forward ...`
command. The caller (agent or human) then runs that string through the Bash
tool. This is deliberate: `~/.claude/hooks/housi-k8s-guard.sh` is a
`PreToolUse` hook that only inspects command *text* — it cannot see what a
wrapper script executes internally. A script that called `kubectl` on the
agent's behalf would silently disable the guard's confirmation prompt for
production and homolog. Never change this. Never wrap the printed command in
`setsid` either — it detaches into a new session the guard can't associate
with the visible command, with the same effect.

Verified empirically (2026-09-21): the retry-wrapped command this skill
generates (`nohup bash -c 'while :; do kubectl ... port-forward ...; ...
done' &`) still surfaces the literal `kubectl ... port-forward ...` segment
to the guard, and prod/homolog still get `ask`. See
`~/.claude/hooks/tests/k8s-guard-test.sh` for the regression test.

## Known limitations

- **Sandbox retry-wrapped commands get no guard decision, not `allow`.** The
  guard's aggregate rule only emits `allow` when *every* segment of the
  command is a recognized kubectl call — `while`/`sleep`/`done` aren't, so a
  retry loop against sandbox falls through to Claude Code's normal
  permission flow (an ordinary approval prompt) instead of being silently
  allowed. This is a minor loss of convenience, not a safety gap.
- **`pf.sh sync` only verifies Service- and StatefulSet-backed curated
  targets**, and only auto-*adds* new targets discovered under the `app`
  namespace role. Datastores/observability targets outside the curated set
  are never auto-added — a human has to add them to `data/registry.yaml`
  (they need engine metadata and, often, a `secret_ref` that can't be safely
  inferred from `kubectl get svc`).
- **Deterministic port allocation for discovered targets** uses
  `cksum(target) % 900` offset from the environment's `local_port_base`,
  with linear probing on collision. It's stable across syncs (the same
  target always gets the same port, assuming the catalog isn't hand-edited
  to remove it) but is not guaranteed collision-free against a port a human
  is using locally for something unrelated — `pf.sh up` always re-checks
  with `lsof` before starting.
- **`down` kills the supervisor's direct children** (via `pgrep -P`) plus
  the supervisor itself. If a forward manages to restart in the exact
  instant `down` runs, there's a narrow race; `_tick` also checks
  `state == stopped` before restarting to close most of that window.
