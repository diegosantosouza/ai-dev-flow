---
name: obs-gap
description: Audit observability coverage for a service — compare metrics declared/instrumented in the local code against what actually arrived in Prometheus/Loki, and flag dead instrumentation or unused signals. Use before adding a new panel or alert, or when investigating "why don't we have data for X".
argument-hint: <service-name>
arguments: service_name
context: fork
agent: observability-analyst
background: false
---

# Observability Gap Audit — `$service_name`

Run your Preflight, then apply your gap protocol for the service `$service_name`.

## Steps

1. Preflight first, as always.
2. **Code side** — `grep` the service for its metric instrument names: `src/shared/tracer/instrument-names.ts` (Node) or the `internal/otel/metrics.go` constants (Go), plus any custom `BaseMetrics` subclasses. List every metric name the code is capable of emitting.
3. **Grafana side** — `list_prometheus_metric_names` filtered to `exported_job="$service_name-api"` (or the job label this service actually uses, confirmed in Preflight). List every metric name actually arriving.
4. **Dashboard side** — if `deploy/grafana/dashboards/*.json` exists in the target repo, `grep` panel `expr` fields for which of the arriving metrics are actually visualized.
5. Compute the three-way diff:
   - Declared in code, never arrived → likely a wiring bug (e.g. a consumer not extending `BaseConsumer`, a cron not extending `BaseCron`) or a code path never exercised yet.
   - Arrived, but no panel references it → dead signal, candidate for `/obs-panel`.
   - Referenced in a panel, but the metric hasn't produced a series in the queried window → possibly the panel is already stale.

## Output

One table: metric name | declared in code | arriving in Prometheus | used in a dashboard panel. Then a short list of concrete next actions (e.g. "wire `OrderConsumer` into `BaseConsumer`", "add a panel for `fulfillment.integration.request_errors`") — only for gaps with clear evidence, not speculative ones.
