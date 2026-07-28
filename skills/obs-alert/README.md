# Skill: `/obs-alert`

Gera uma regra de alerta nova para um serviço já instrumentado, como arquivo versionado em `deploy/grafana/alerts/`, com threshold derivado de dados reais do Prometheus.

## Por que `disable-model-invocation: true`

Criar um alerta é uma decisão humana — não queremos o modelo decidindo por conta própria que "é hora de criar um alerta" no meio de outra tarefa. Esta skill só roda quando invocada explicitamente com `/obs-alert`.

## O que a Skill faz

1. Roda o Preflight do agent `observability-builder`.
2. Consulta o histórico real da métrica e propõe um threshold baseado em baseline/p95 observado — não um número arbitrário.
3. Escreve a regra em `deploy/grafana/alerts/<service>-alert-rules.yaml`, no formato de provisioning do Grafana Alerting já usado por `otel-bootstrap`.
4. Define `severity` (`critical`/`warning`) conforme a urgência da condição.

## Pré-requisitos

Os mesmos do `/obs-panel`.

## Como usar

```bash
cd ~/projetos/fulfillment-svc
claude

/obs-alert fulfillment taxa de nack do consumer acima do normal
```

## Próximo passo

O arquivo gerado **não é aplicado automaticamente**. Revise e use [`/obs-apply`](../obs-apply/README.md).
