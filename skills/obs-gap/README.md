# Skill: `/obs-gap`

Audita a cobertura de observabilidade de um serviço: compara o que o código instrumenta com o que de fato chegou no Prometheus/Loki, e aponta instrumentação morta ou sinais sem painel.

## O que a Skill faz

1. Roda o **Preflight** do agent `observability-analyst`.
2. Lista as métricas declaradas no código (`instrument-names.ts`, `BaseMetrics`, ou equivalente Go).
3. Lista as métricas que realmente chegam no Prometheus, filtradas por `exported_job`.
4. Cruza com os painéis existentes em `deploy/grafana/dashboards/` (se houver).
5. Reporta o diff de três vias: declarado-sem-chegar (bug de wiring), chegando-sem-painel (candidato a `/obs-panel`), painel-sem-dado (painel possivelmente obsoleto).

## Pré-requisitos

Os mesmos do [`/obs-rca`](../obs-rca/README.md): ai-dev-flow instalado, `mcp-grafana` no `PATH`, `GRAFANA_URL`/`GRAFANA_SERVICE_ACCOUNT_TOKEN` preenchidos no `.env`, service account Viewer.

## Como usar

```bash
cd ~/projetos/fulfillment-svc
claude

/obs-gap fulfillment
```

O argumento é o nome do serviço, no mesmo formato usado por `/otel-bootstrap`.
