---
name: obs-panel
description: Generate a new Grafana dashboard panel for an already-instrumented service, written as a versioned file under deploy/grafana/dashboards/. Use after /obs-gap surfaces a metric with no panel, or when you know what you want visualized.
argument-hint: <service-name> <what to visualize>
arguments: [service_name]
context: fork
agent: observability-builder
background: false
---

# New Panel — `$service_name`

Full invocation as typed: **$ARGUMENTS**

The first word is the service name (`$service_name`). Everything after it — read it from the full invocation above, not from any truncated single-word field — is the description of what to visualize. Multi-word descriptions (a metric name, a phrase like "heatmap of X broken down by Y") are the normal case; parse the whole remainder yourself, don't assume it's one word.

Generate a panel (or new dashboard, if none fits) visualizing that description, for service `$service_name`.

## Steps

1. Preflight — confirm the metric(s) named in the description actually exist for `$service_name` before writing anything. If the description doesn't name a specific metric, ask yourself what it implies rather than substituting an unrelated metric you happen to find first.
2. Pick the dashboard file the panel belongs in; append rather than create a near-duplicate.
3. Follow the repo's PromQL and panel-type conventions.
4. Validate (`jq .`, placeholder grep) on every file you touched.

## Output

Path(s) written, the panel title, the query, and the validation result. Remind the user this is a file, not yet applied to Grafana — `/obs-apply` handles that.
