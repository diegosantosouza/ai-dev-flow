# Skill: `/obs-panel`

Gera um painel novo de dashboard Grafana para um serviço já instrumentado, como arquivo versionado em `deploy/grafana/dashboards/`.

## O que a Skill faz

1. Roda o Preflight do agent `observability-builder` — confirma que a métrica pedida existe antes de escrever qualquer coisa.
2. Decide se o painel entra num dashboard existente ou se um novo arquivo é necessário.
3. Segue as convenções de PromQL e tipo de painel já estabelecidas por `otel-bootstrap` (filtro `exported_job`, `* 60`/`reqpm` em rates absolutos, etc).
4. Valida (`jq .`, ausência de placeholders) antes de reportar.

## Pré-requisitos

Os mesmos do `/obs-rca`, mais: o serviço alvo já deve ter passado por `/otel-bootstrap` (ou já ter `deploy/grafana/` com o mesmo layout).

## Como usar

```bash
cd ~/projetos/fulfillment-svc
claude

/obs-panel fulfillment latência p99 do consumer de pedidos
```

## Próximo passo

O arquivo gerado **não é aplicado automaticamente** no Grafana. Revise o diff e use [`/obs-apply`](../obs-apply/README.md) quando estiver pronto para publicar.
