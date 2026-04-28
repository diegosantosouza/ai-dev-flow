---
name: otel-bootstrap
description: Bootstrap the Housi OpenTelemetry observability pattern (tracer, custom metrics, Grafana dashboards, alert rules) into a Node.js/TypeScript or Go microservice. Detects service components automatically (HTTP, PubSub consumers, cron jobs) and generates only what applies. Use when onboarding a new service to the Housi observability standard.
argument-hint: <service-name>
arguments: service_name
allowed-tools: Read, Write, Edit, Glob, Grep, Bash
---

# OTel Bootstrap — `$service_name`

You are implementing the Housi observability standard in the **current working directory** (the target service). Templates live in `${CLAUDE_SKILL_DIR}/templates/`.

## Variables

| Placeholder | Value | Example |
|---|---|---|
| `{{SERVICE_NAME}}` | `$service_name` (lowercase) | `fulfillment` |
| `{{SERVICE_UPPER}}` | `$service_name` uppercased | `FULFILLMENT` |
| `{{SERVICE_PREFIX}}` | `$service_name.` (with dot) | `fulfillment.` |
| `{{SERVICE_PASCAL}}` | `$service_name` PascalCase | `Fulfillment` |
| `{{EXPORTED_JOB}}` | `$service_name-api` | `fulfillment-api` |

Compute SERVICE_UPPER, SERVICE_PASCAL and EXPORTED_JOB from `$service_name` before starting.

---

## Step 1 — Detect language and components

Read `package.json` or `go.mod` in the current directory and determine:

**Language detection:**
- If `package.json` exists → `language = node`
- If `go.mod` exists → `language = go`
- If both exist → use `node` (log a warning)
- If neither → stop and ask the user

**Component detection (Node):**
- `has_http = true` if `"express"`, `"fastify"` or `"@nestjs/core"` appears in `dependencies` or `devDependencies`
- `has_pubsub = true` if `"@google-cloud/pubsub"` appears in `dependencies`
- `has_cron = true` if directory `src/crons/` exists OR `"node-cron"` appears in `dependencies`

**Component detection (Go):**
- `has_http = true` if `go.mod` contains `github.com/gin-gonic/gin`, `github.com/labstack/echo`, `github.com/go-chi/chi` or `net/http` usage in `*.go` files
- `has_pubsub = true` if `go.mod` contains `cloud.google.com/go/pubsub`
- `has_cron = true` if `go.mod` contains `github.com/robfig/cron` OR directory `cmd/cron/` or `internal/cron/` exists

Print a summary before proceeding:
```
Detected: language=<node|go> has_http=<true|false> has_pubsub=<true|false> has_cron=<true|false>
```

---

## Step 2 — Check for existing observability

Before writing any file, check if observability already exists:
- **Node:** look for `src/shared/tracer/` directory
- **Go:** look for files named `tracer.go` or `otel.go` anywhere under `internal/` or `pkg/`

If found, **do not overwrite**. Instead:
1. Show what already exists
2. Identify gaps vs the standard
3. Ask the user whether to patch gaps or abort

---

## Step 3 — Render and write files

Use the render logic: for each template file, replace ALL placeholders before writing. Never write a file that still contains `{{SERVICE_NAME}}`, `{{SERVICE_UPPER}}`, `{{SERVICE_PREFIX}}`, `{{SERVICE_PASCAL}}` or `{{EXPORTED_JOB}}` literally — those must all be substituted.

### Node.js — always write (core tracer infrastructure)

Write these files to the target service. Source templates are in `${CLAUDE_SKILL_DIR}/templates/node/`:

| Template | Target path |
|---|---|
| `tracer.ts.tmpl` | `src/shared/tracer/tracer.ts` |
| `bootstrap.ts.tmpl` | `src/shared/tracer/bootstrap.ts` |
| `grpc-exporter.ts.tmpl` | `src/shared/tracer/grpc-exporter.ts` |
| `http-exporter.ts.tmpl` | `src/shared/tracer/http-exporter.ts` |
| `instrument-names.ts.tmpl` | `src/shared/tracer/instrument-names.ts` |
| `attributes.ts.tmpl` | `src/shared/tracer/attributes.ts` |
| `metrics/base-metrics.ts.tmpl` | `src/shared/tracer/metrics/base-metrics.ts` |
| `metrics/integration-metrics.ts.tmpl` | `src/shared/tracer/metrics/integration-metrics.ts` |

Create the `src/shared/tracer/metrics/` directory if it does not exist.

### Node.js — conditional on `has_pubsub`

| Template | Target path |
|---|---|
| `metrics/pubsub-metrics.ts.tmpl` | `src/shared/tracer/metrics/pubsub-metrics.ts` |
| `base-classes/base.consumer.ts.tmpl` | `src/consumers/base.consumer.ts` |

If `src/consumers/base.consumer.ts` already exists: use Edit to **add** the OTel instrumentation (import PubSubMetrics, record spans and metrics) rather than overwrite. Read the existing file first and insert only what is missing.

### Node.js — conditional on `has_cron`

| Template | Target path |
|---|---|
| `metrics/cron-metrics.ts.tmpl` | `src/shared/tracer/metrics/cron-metrics.ts` |
| `base-classes/base.cron.ts.tmpl` | `src/crons/base.cron.ts` |

Same patch logic: if file exists, augment rather than overwrite.

### Go — always write (core tracer infrastructure)

| Template | Target path |
|---|---|
| `go/tracer.go.tmpl` | `internal/otel/tracer.go` |
| `go/bootstrap.go.tmpl` | `internal/otel/bootstrap.go` |
| `go/metrics.go.tmpl` | `internal/otel/metrics.go` |

> ⚠️ **Go templates are v0.1 — validate against a real Go service before using in production.**

### Go — conditional on `has_http`

| Template | Target path |
|---|---|
| `go/http_middleware.go.tmpl` | `internal/otel/http_middleware.go` |

### Go — conditional on `has_pubsub`

| Template | Target path |
|---|---|
| `go/pubsub_consumer.go.tmpl` | `internal/otel/pubsub_consumer.go` |

### Go — conditional on `has_cron`

| Template | Target path |
|---|---|
| `go/cron.go.tmpl` | `internal/otel/cron.go` |

---

## Step 4 — Grafana dashboards and alerts

Templates are in `${CLAUDE_SKILL_DIR}/templates/grafana/`. Write rendered files to `deploy/grafana/dashboards/` and `deploy/grafana/alerts/` in the target service. Create those directories if they don't exist.

**Always write:**
- `golden-signals.json.tmpl` → `deploy/grafana/dashboards/{{SERVICE_NAME}}-golden-signals.json`

**Conditional on `has_http` (or always — HTTP is standard for APIs):**
- `service-health.json.tmpl` → `deploy/grafana/dashboards/{{SERVICE_NAME}}-service-health.json`

**Conditional on `has_pubsub`:**
- `messaging.json.tmpl` → `deploy/grafana/dashboards/{{SERVICE_NAME}}-messaging.json`

**Conditional on `has_cron`:**
- `crons.json.tmpl` → `deploy/grafana/dashboards/{{SERVICE_NAME}}-crons.json`

**Always write:**
- `integration-errors.json.tmpl` → `deploy/grafana/dashboards/{{SERVICE_NAME}}-integration-errors.json`
- `alerts/alert-rules.yaml.tmpl` → `deploy/grafana/alerts/{{SERVICE_NAME}}-alert-rules.yaml`

---

## Step 5 — Update package.json (Node only)

Check if `@opentelemetry/auto-instrumentations-node` and `@opentelemetry/sdk-node` are already in `dependencies`. If not, print the exact `npm install` command the user needs to run (do not run it automatically — it may change the lockfile):

```
npm install --save @opentelemetry/sdk-node@^0.207.0 @opentelemetry/auto-instrumentations-node@^0.66.0
```

Check if the `start` script in `package.json` already requires the tracer bootstrap. If not, show the user what to add:
```json
"start": "node --require ./dist/shared/tracer/bootstrap.js <current-start-command>"
```

---

## Step 6 — Validate

Run these checks and report results:

**Node:**
```bash
# Validate dashboard JSONs
for f in deploy/grafana/dashboards/*.json; do jq . "$f" > /dev/null && echo "OK: $f" || echo "INVALID: $f"; done
# Check no unreplaced placeholders remain
grep -r "{{SERVICE" deploy/grafana/ src/shared/tracer/ && echo "WARNING: unreplaced placeholders found" || echo "OK: no placeholders remain"
```

**Go:**
```bash
for f in deploy/grafana/dashboards/*.json; do jq . "$f" > /dev/null && echo "OK: $f" || echo "INVALID: $f"; done
grep -r "{{SERVICE" deploy/grafana/ internal/otel/ && echo "WARNING: unreplaced placeholders found" || echo "OK: no placeholders remain"
```

---

## Acceptance criteria

- [ ] All template placeholders replaced — no `{{SERVICE_NAME}}` etc. in generated files
- [ ] All Grafana dashboard JSONs are valid (`jq .` returns 0)
- [ ] All PromQL queries contain `exported_job="{{EXPORTED_JOB}}"` filter
- [ ] Node: `src/shared/tracer/tracer.ts` uses `__{{SERVICE_NAME}}_otel_sdk__` global key
- [ ] Node: metric names in `instrument-names.ts` use `{{SERVICE_NAME}}.` prefix
- [ ] Go: all generated `.go` files have correct package declarations
- [ ] No domain-specific code from the reference service in generated files (business metrics, proprietary integrations, internal decorators)
