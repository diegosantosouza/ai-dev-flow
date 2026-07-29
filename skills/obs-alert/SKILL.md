---
name: obs-alert
description: Generate a new Grafana alert rule for an already-instrumented service, written as a versioned file under deploy/grafana/alerts/, with a threshold derived from real metric history. Only invoke this directly — deciding to add an alert is a human call.
argument-hint: <service-name> <condition to alert on>
arguments: [service_name]
context: fork
agent: observability-builder
disable-model-invocation: true
background: false
---

# New Alert — `$service_name`

Full invocation as typed: **$ARGUMENTS**

The first word is the service name (`$service_name`). Everything after it — read it from the full invocation above, not from any truncated single-word field — is the condition to alert on. Conditions are normally multi-word (e.g. "nack rate above normal", "p99 latency over 2s"); parse the whole remainder yourself.

Generate an alert rule for that condition, for service `$service_name`.

## Steps

1. Preflight — confirm the metric(s) implied by the condition exist for `$service_name`.
2. Query recent history for that metric via the `grafana` MCP and derive a threshold from the observed baseline/p95 — state what you based it on. Don't pick an arbitrary round number.
3. Write the rule into `deploy/grafana/alerts/<service>-alert-rules.yaml` (append to `groups` if the file exists), following the repo's alert-rule shape.
4. Set `severity` based on whether this condition needs immediate action (`critical`) or is a heads-up (`warning`).
5. Validate the YAML and check for leftover placeholders.

## Output

Path written, the rule's condition/threshold and why, the `severity` chosen, and the validation result. Remind the user this is a file, not yet active in Grafana — `/obs-apply` handles that, after they review it.
