---
name: k8s
description: Run kubectl actions (get, describe, logs, restart, scale, exec, port-forward, etc.) against the Housi Kubernetes environments — sandbox, homolog, and production — always with explicit --context and --namespace, discovering service/deployment names and ports at runtime instead of assuming them. Production and homolog share one GKE cluster (gke-prd-housi-01), distinguished only by namespace; a separate PreToolUse hook (housi-k8s-guard.sh) asks for confirmation before any state-changing command or port-forward reaches that cluster — that prompt is expected, not an error. Use whenever the user wants to inspect, restart, scale, exec into, or tunnel into a Housi service running in Kubernetes.
argument-hint: <action> <service> [--env sandbox|homolog|prod] [kubectl args...]
allowed-tools: Bash, Read, Grep, Glob
---

# Housi Kubernetes Operations

Full invocation as typed: **$ARGUMENTS**

This skill does not reimplement kubectl. It loads the Housi environment map below,
enforces a couple of safety conventions, and then runs plain `kubectl` through the
Bash tool. A separate hook (`~/.claude/hooks/housi-k8s-guard.sh`) independently
inspects every `kubectl` call and will pop a confirmation prompt for anything that
mutates state, or opens a port-forward, on the production cluster — including the
`apps-hml` (homolog) namespace, since it lives on that same cluster. If that prompt
appears, show it to the user as-is; it is the intended safety net, not a failure.

## Environment map

| `--env` | GCP project | Cluster (us-east1) | kubectl context | Namespace |
|---|---|---|---|---|
| `sandbox` | `prj-dev-housi-sandbox-01` | `gke-dev-housi-01` | `gke_prj-dev-housi-sandbox-01_us-east1_gke-dev-housi-01` | `sandbox` |
| `homolog` | `prj-prd-housi-sandbox-01` | `gke-prd-housi-01` | `gke_prj-prd-housi-sandbox-01_us-east1_gke-prd-housi-01` | `apps-hml` |
| `prod` | `prj-prd-housi-sandbox-01` | `gke-prd-housi-01` | `gke_prj-prd-housi-sandbox-01_us-east1_gke-prd-housi-01` | `apps` |

`homolog` and `prod` are the **same cluster and the same kubectl context** — only the
namespace differs. Production consumers and cron jobs live on that same cluster in the
`consumers` and `cronjobs` namespaces respectively, when the target service has those
components (check `severino-v2/deploy/_config.yml` for an example of this split).

Source of truth for this map: `severino-v2/.github/workflows/deploy-{sandbox,homolog-gcp,production-gcp}.yml`
and `severino-v2/deploy/_config.yml`. If a service's CI workflow uses a different
cluster/project, defer to that workflow over this table.

## Rules

1. **Always pass `--context` and `--namespace` explicitly on every kubectl call.**
   Never rely on the ambient `current-context`. This is both a safety property (the
   guard hook resolves the effective target either way, but explicit flags remove all
   ambiguity for a human reading the transcript) and a friendliness property: commands
   with `--context`/`--namespace` already present pass through the `rtk` hook
   unmodified, while a bare `kubectl get pods` gets rewritten.

2. **Never run `kubectl config use-context`.** It mutates the user's ambient kubectl
   state for every future terminal command, not just this session. Switch environments
   by changing the `--context`/`--namespace` flags on each command instead.

3. **Resource naming**: for services deployed the way `severino-v2` is (see
   `severino-v2/deploy/severino.yml`), the convention is `<service>-deployment`,
   `<service>-service`, and for consumers `<service>-<consumer-name>-deploy`. Treat this
   as a *starting guess*, not a fact — confirm with `kubectl get deploy,svc -n <ns>
   --context <ctx>` before acting on a name you haven't verified this session, since not
   every Housi service necessarily follows the same manifest template.

4. **Ports are templated per environment, never hardcoded.** `severino-v2/deploy/_config.yml`
   shows `servicePort` varying by stage. Before a port-forward, discover the real port:
   ```
   kubectl --context <ctx> -n <ns> get svc <service>-service -o jsonpath='{.spec.ports[0].port}'
   ```

5. **Port-forward runs as a background Bash process** (`run_in_background: true`) so it
   outlives the current turn and can be stopped deliberately, rather than tying up a
   foreground call:
   ```
   kubectl --context <ctx> -n <ns> port-forward svc/<service>-service <local-port>:<remote-port>
   ```
   Tell the user the local port and how to stop it (kill the background shell, or
   `pkill -f "port-forward svc/<service>-service"`).

6. **If `--env` is missing or ambiguous, ask** — don't default silently to any
   environment, sandbox included. Getting the environment wrong is the one mistake this
   skill exists to prevent.

## Steps

1. Parse `$ARGUMENTS` for the action (get/describe/logs/restart/scale/exec/port-forward/...),
   the target service, `--env`, and any pass-through kubectl flags/args.
2. Resolve `--context`/`--namespace` from the environment map above. If `--env prod` was
   requested for a consumer/cronjob workload, use the `consumers`/`cronjobs` namespace
   instead of `apps` — ask if it's unclear which.
3. If the action needs a resource name you haven't confirmed this session (deployment,
   service, pod), run a quick `kubectl get` first rather than guessing from the naming
   convention.
4. Build and run the full kubectl command with explicit `--context`/`--namespace`. For
   `port-forward`, discover the port first (rule 4) and run it in the background (rule 5).
5. If the guard hook's confirmation prompt appears, relay it plainly — do not try to
   reword it as a lesser warning or add a workaround.
6. Report the actual kubectl output back to the user; don't paraphrase error messages
   from RBAC/`Forbidden` responses, they usually point at the exact missing permission.
