---
name: obs-rca
description: Investigate an error, log pattern, or trace ID by correlating Grafana (logs, metrics, traces) with the local codebase, to find where a failure most likely originated. Use when a bug report, alert, or error message needs a root cause before it can be fixed.
argument-hint: <error description | trace-id | time window>
context: fork
agent: observability-analyst
background: false
---

# Root Cause Analysis

Full invocation as typed: **$ARGUMENTS**

That is the entire target to investigate — read it as-is, not split into words. It may be an error message, a Loki/Tempo trace ID, a time window (e.g. "last 30 minutes"), or a mix (e.g. "500s on /checkout since 14:00"), almost always multi-word. Infer which shape it is from the text; don't assume only the first word matters.

Run your Preflight, then apply your root-cause protocol to it.

## Steps

1. Preflight (datasources, Tempo MCP availability) — report it first, always.
2. If the target names or implies a service, scope every query to that service's `exported_job`.
3. Cluster before reading raw lines (`query_loki_patterns`) when the search isn't already narrowed to a handful of log lines.
4. Run the hypothesis loop from your root-cause protocol. Read the local code paths your evidence points to — don't stop at the log line, confirm against the actual source (mind the source-map caveat for Node/TS stack traces).
5. If a hypothesis reaches **root cause**, state the fix location (file + function, not just a line number if source maps are unconfirmed) but do not edit anything — this skill is read-only.

## Output

Follow your standard output format. Add one line at the end: whether this failure pattern looks like something `/obs-alert` should cover going forward (a threshold that would have caught it earlier) — only if there's a clear metric already available for it, don't invent one.
