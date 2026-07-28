---
name: obs-panel
description: Generate a new Grafana dashboard panel for an already-instrumented service, written as a versioned file under deploy/grafana/dashboards/. Use after /obs-gap surfaces a metric with no panel, or when you know what you want visualized.
argument-hint: <service-name> <what to visualize>
arguments: [service_name, request]
context: fork
agent: observability-builder
background: false
---

# New Panel — `$service_name`: $request

Generate a panel (or new dashboard, if none fits) visualizing: **$request**, for service `$service_name`.

## Steps

1. Preflight — confirm the metric(s) needed for "$request" actually exist for `$service_name` before writing anything.
2. Pick the dashboard file the panel belongs in; append rather than create a near-duplicate.
3. Follow the repo's PromQL and panel-type conventions.
4. Validate (`jq .`, placeholder grep) on every file you touched.

## Output

Path(s) written, the panel title, the query, and the validation result. Remind the user this is a file, not yet applied to Grafana — `/obs-apply` handles that.
