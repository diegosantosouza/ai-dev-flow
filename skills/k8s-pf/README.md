# Skill: `/k8s-pf`

Opens and supervises `kubectl port-forward` tunnels into Housi's sandbox,
homolog, and production Kubernetes environments from a pre-mapped registry —
no live `kubectl get` needed to find a service's name or port on the happy
path.

## Why this exists, separate from `/k8s`

The `k8s` skill (`skills/k8s/`) discovers everything at runtime by design —
that's the right default for arbitrary `kubectl` actions (`get`, `describe`,
`logs`, `exec`, ...) where the target and its shape can't be known ahead of
time. Port-forwarding is different: the same handful of targets get tunneled
over and over (an app service, a database, the OTel collector), the
environments are asymmetric in ways worth writing down once (in sandbox,
databases live in their own namespaces — `mysql`, `postgres`, `redis`; in
production the same databases live inside the `apps` namespace), and a
single open tunnel is rarely enough — you usually want the app *and* its
database *and* a trace backend forwarded at the same time, staying open,
reconnecting on their own if they drop.

So `k8s` keeps its rule 4/5 pointing here for port-forward specifically
(see `skills/k8s/SKILL.md`), and this skill owns: the registry, multi-tunnel
supervision with reconnect/backoff, and the self-refresh (`sync`) that keeps
the registry from going stale as services are added.

## Architecture in one paragraph

`data/registry.yaml` is the curated source of truth (environments,
namespaces-by-role, and every target with its `resource`, ports, and risk) —
edit this by hand, then run `pf.sh compile` (needs `yq`) to regenerate
`data/catalog.json`, the flat, `jq`-only artifact the runtime actually reads.
`pf.sh sync` additionally discovers new app-namespace services live from the
cluster (read-only `kubectl get`) and folds them into the same catalog as
`source: discovered`, without ever touching the curated layer. Both files
are committed — a new service appearing is a reviewable git diff, not silent
state. See `SKILL.md` for the full command reference and the security
property that makes this safe for production (`up` never runs `kubectl`
itself; it prints the command for the agent to run, so the exact command
text stays visible to `~/.claude/hooks/housi-k8s-guard.sh`).

## Runtime state

Per-forward state (PID, log, restart count) lives outside the skill
directory, at `${HOUSI_PF_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/housi-pf}/forwards/<id>/`
— the skill directory itself is a symlinked git checkout and shouldn't hold
mutable runtime state.

## Maintaining the registry

```bash
cd ~/projetos/ai-dev-flow/skills/k8s-pf

# after hand-editing data/registry.yaml:
bash scripts/pf.sh compile          # needs yq; regenerates data/catalog.json

# to pick up services deployed since the last sync:
bash scripts/pf.sh sync --all       # read-only kubectl get, safe to run anytime
bash scripts/pf.sh sync --all --dry-run   # preview the diff without writing
```

`yq` is only needed for `compile` (editing `registry.yaml`). Day-to-day use
(`plan`, `up`, `status`, `list`, `sync`) needs only `jq` and `kubectl`.

## Known, accepted gaps (see the k8s-pf implementation plan for the full list)

- Datastore/observability targets are never auto-added by `sync` — only
  auto-*verified* if they're Service- or StatefulSet-backed. A new database
  needs a human to add it to `registry.yaml` with its `secret_ref`.
- A retry-wrapped sandbox command gets no guard decision at all (falls
  through to Claude Code's normal permission flow) rather than a silent
  `allow`, because the guard's aggregate rule requires every segment of the
  command to be a recognized kubectl call, and `while`/`sleep` aren't. Minor
  convenience loss, not a safety gap.
- There are three places that describe the environment map (`skills/k8s/SKILL.md`,
  `~/.claude/hooks/housi-k8s-guard.sh`'s signal lists, and this skill's
  `registry.yaml`) with no automated consistency check between them yet.
