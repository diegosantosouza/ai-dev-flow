---
name: k8s-pf
description: Opens, supervises, and lists kubectl port-forward tunnels into Housi's sandbox, homolog, and production environments from a pre-mapped registry of app services (e.g. severino-v2), StatefulSet-backed databases (MySQL, Postgres, Redis, Elasticsearch), and observability services (OpenTelemetry collector, Tempo, Loki, Grafana, Prometheus) — no live kubectl discovery needed on the happy path. Supports multiple simultaneous tunnels, automatically reconnects a dropped tunnel with backoff, reports clear errors when a tunnel can't open, and re-syncs its map from the cluster when a target is unknown or a new service was deployed. Use whenever the user asks to "open a port-forward", "tunnel into X", "connect to severino-v2 in sandbox", "acessar o banco de homolog", "conectar no otel collector", "abrir port-forward para produção", or similar — in English or Portuguese — and also when another skill or agent needs a local connection to a Housi Kubernetes service to run further commands against it.
argument-hint: <target> [--env sandbox|homolog|prod] [--port name] [--local-port N] | status [--deep] | list | down <id|--all> | logs <id> | sync (--env E|--all) | doctor
allowed-tools: Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh status:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh plan:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh list:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh logs:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh doctor:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh sync:*), Bash(bash ${CLAUDE_SKILL_DIR}/scripts/pf.sh down:*), Read, Grep
---

# Housi k8s port-forward manager

Full invocation as typed: **$ARGUMENTS**

## The one rule that matters

**`pf.sh` never runs `kubectl` itself.** `plan` and `up` resolve the target
against the registry and **print** the exact `kubectl ... port-forward ...`
command; you (the agent) then run that exact string through the Bash tool.

This is not a style choice — it's load-bearing. `~/.claude/hooks/housi-k8s-guard.sh`
is a `PreToolUse` hook that inspects the *text* of every Bash command and
requires confirmation before a port-forward reaches the production cluster
(`gke-prd-housi-01`, which hosts both `apps` and `apps-hml`/homolog). It
cannot see what a wrapper script executes internally — a script that called
`kubectl` on your behalf would silently disable that confirmation for
production and homolog. So:

- Wrapping is fine for read-only kubectl verbs (`get`, `describe`, ...) —
  the guard allows those everywhere regardless of wrapping.
- Wrapping is **forbidden** for `up`'s printed command and any other
  mutating/port-forward call. Run the printed string exactly as given.
- **Never** prepend `setsid` to it, and never otherwise re-wrap it — both
  detach it from the command text the guard is inspecting.
- If the guard's confirmation prompt appears, relay it to the user as-is.
  That's the intended safety net, not a failure — same rule as the `k8s`
  skill (see its SKILL.md rule 5).

## Quick reference

```
pf.sh plan   <target> [--env E] [--port NAME] [--local-port N] [--json]   # resolve + preview, no state written
pf.sh up     <target> [--env E] [--port NAME] [--local-port N] [--json]   # resolve + prints the command to run
pf.sh status [--deep] [--json] [<id>]                                     # all open forwards (--deep = real TCP probe)
pf.sh list   [--env E] [--json]                                          # everything the catalog knows, no cluster call
pf.sh down   <id>|--all                                                  # stop one or every forward
pf.sh logs   <id> [-n N]                                                 # tail a forward's kubectl log
pf.sh sync   (--env E|--all) [--dry-run]                                 # refresh the catalog from the live cluster
pf.sh doctor                                                              # deps, auth, catalog age, orphaned forwards
```

`<target>` is a name or alias from `data/registry.yaml` (e.g. `severino-v2`,
`severino`, `mysql`, `otel`, `tempo`, `grafana`). Run `pf.sh list` to see
everything currently mapped, per environment, with no cluster round-trip.

## Steps

1. **Resolve target + env.** Run `pf.sh plan <target> --env <env>` first if
   you want to preview without opening anything, or go straight to `up`.
   If `--env` is missing or you're not sure which environment the user
   means, **ask** — don't default to sandbox or anything else (exit code 4
   means exactly this: the script is telling you to ask).
2. **If the target is unknown** (exit 3), `pf.sh` already tried one
   auto-sync of that environment before giving up — trust the *did-you-mean*
   suggestion, or run `pf.sh sync --all` yourself if the service was very
   recently deployed and might be in a different namespace role.
3. **If risk is `critical`** (shown in `plan`/`up`'s output — always the
   case for a production datastore), confirm with the user via
   `AskUserQuestion` before running the printed command, even though the
   guard hook will also prompt. Defense in depth: two independent checks
   for the most dangerous action this skill can take.
4. **Run the exact printed command** via the Bash tool. If it targets
   sandbox, it may pass through without a guard decision at all (a retry
   loop's `while`/`sleep` scaffolding isn't a recognized kubectl segment, so
   the aggregate "allow" rule doesn't fire — you may see an ordinary
   permission prompt instead; that's expected, not an error). If it targets
   homolog/prod, the guard will ask — relay that prompt plainly.
5. **Report the id, local port, and log path** back to the user (`up`
   prints all three). Tell them how to check on it (`pf.sh status <id>`) and
   how to stop it (`pf.sh down <id>`).
6. **For multiple simultaneous tunnels**, just call `up` again for each
   target — each gets its own id, log, and supervisor. `pf.sh status` (no
   id) lists all of them at once.
7. **If a tunnel misbehaves**, `pf.sh logs <id>` shows the supervisor's own
   trace (retries, backoff, fatal classification) interleaved with
   kubectl's own output — usually enough to tell whether it's transient
   (auto-reconnecting) or fatal (see `reference/troubleshooting.md` for the
   exit-code table and what each one means).

## What's mapped, and what isn't

`data/registry.yaml` (curated by hand) plus `data/catalog.json` (compiled +
auto-synced) together cover: the three environments' contexts/namespaces,
`severino-v2` as the example app target, the StatefulSet-backed databases
(MySQL, Postgres, Redis, Elasticsearch), and the observability stack
(OpenTelemetry collector, Tempo, Loki, Grafana, Prometheus) — with real
ports and resource names verified live against the cluster, not assumed.
Every other app-namespace service in both clusters is also mapped as a
"discovered" target from the initial `pf.sh sync --all`.

**Auto-reciclagem**: when a target genuinely isn't in the catalog yet (a
brand-new service), the *first* lookup triggers one automatic sync of that
environment before failing — so the very next attempt (or the same command,
re-run) picks it up with no manual `sync` step. `pf.sh sync --all` also runs
on demand, and `status`/`doctor` warn (stderr only, never blocking) when the
catalog is more than 7 days old.

New datastore/observability targets are **never** auto-added — they need a
human to add `ns_role`, `resource`, and (for databases) a `secret_ref` to
`data/registry.yaml`, then run `pf.sh compile` (needs `yq`). This is a
deliberate asymmetry: getting an app service's port wrong is a minor
annoyance; guessing a database's connection details wrong is not something
to automate.

## Multi-tunnel, reconnection, and errors — how they actually work

- Every open forward is a self-contained slot under
  `${HOUSI_PF_STATE_DIR:-~/.local/state/housi-pf}/forwards/<id>/` (its own
  PID file, state, log, restart counter) — opening N targets means N
  independent slots, no shared state to corrupt.
- The command `up` prints wraps the real `kubectl port-forward` in a retry
  loop: on any exit, an internal `pf.sh _tick` call classifies the failure
  (a local bind conflict or an auth error is fatal, and stops immediately;
  anything else is transient) and sleeps a backoff (1→2→4→8→15s) before the
  loop tries again — up to 20 restarts per 5 minutes, after which it gives
  up and marks the forward `failed` rather than spinning forever.
- Every local port is checked with `lsof` before `up` starts anything; if
  it's already held by something that isn't our own tunnel, `up` refuses
  with exit 5 and names the owning process, instead of masking a real
  conflict.

See `reference/troubleshooting.md` for the full exit-code table and known
limitations.
