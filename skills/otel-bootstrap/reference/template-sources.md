# Mapeamento: Templates ↔ Arquivos-fonte de Referência

Cada template foi extraído do **serviço de referência** — o primeiro serviço da organização a implementar o padrão OTel completo. Quando esse serviço atualizar um arquivo, o template correspondente deve ser ressincronizado.

## Node.js / TypeScript

| Template | Arquivo-fonte de referência | Mudanças aplicadas para parametrização |
|---|---|---|
| `templates/node/tracer.ts.tmpl` | `src/shared/tracer/tracer.ts` | chave global `__<ref>_otel_sdk__` → `__{{SERVICE_NAME}}_otel_sdk__` |
| `templates/node/bootstrap.ts.tmpl` | `src/shared/tracer/bootstrap.ts` | fallback hardcoded com nome do serviço de referência → `'{{SERVICE_NAME}}'` |
| `templates/node/grpc-exporter.ts.tmpl` | `src/shared/tracer/grpc-exporter.ts` | sem mudanças (já genérico) |
| `templates/node/http-exporter.ts.tmpl` | `src/shared/tracer/http-exporter.ts` | sem mudanças (já genérico) |
| `templates/node/instrument-names.ts.tmpl` | `src/shared/tracer/instrument-names.ts` | prefixo do serviço de referência → `{{SERVICE_PREFIX}}`; removidas constantes de domínio exclusivas (`SYNC_*`, `ORDER_SPLIT_*` ou equivalentes) |
| `templates/node/attributes.ts.tmpl` | `src/shared/tracer/attributes.ts` | `<REF>_ATTR` → `{{SERVICE_UPPER}}_ATTR`; removidos atributos de domínio (IDs de entidades de negócio, integrações específicas); mantidos os genéricos: `RESOURCE_TYPE`, `RESOURCE_ID`, `CORRELATION_ID`, `OPERATION`, `OUTCOME`, `ERROR_TYPE` |
| `templates/node/metrics/base-metrics.ts.tmpl` | `src/shared/tracer/metrics/base-metrics.ts` | fallback com nome do serviço de referência → `'{{SERVICE_NAME}}'` |
| `templates/node/metrics/pubsub-metrics.ts.tmpl` | `src/shared/tracer/metrics/pubsub-metrics.ts` | `<REF>_ATTR` → `{{SERVICE_UPPER}}_ATTR` nos imports e uso |
| `templates/node/metrics/cron-metrics.ts.tmpl` | `src/shared/tracer/metrics/cron-metrics.ts` | `<REF>_ATTR` → `{{SERVICE_UPPER}}_ATTR` |
| `templates/node/metrics/integration-metrics.ts.tmpl` | `src/shared/tracer/metrics/integration-metrics.ts` | atributo de domínio específico substituído por `'{{SERVICE_NAME}}.integration.target'` genérico |
| `templates/node/base-classes/base.consumer.ts.tmpl` | `src/consumers/base.consumer.ts` | `<REF>_ATTR` → `{{SERVICE_UPPER}}_ATTR`; removido validador de config acoplado ao serviço de referência |
| `templates/node/base-classes/base.cron.ts.tmpl` | `src/crons/base.cron.ts` | `<REF>_ATTR` → `{{SERVICE_UPPER}}_ATTR`; removido validador de config acoplado ao serviço de referência |

## Grafana Dashboards

| Template | Arquivo-fonte de referência | Mudanças aplicadas |
|---|---|---|
| `templates/grafana/dashboards/golden-signals.json.tmpl` | `deploy/grafana/dashboards/<ref>-golden-signals.json` | prefixo de métricas `<ref>_*` → `{{SERVICE_NAME}}_*`; título → `{{SERVICE_PASCAL}}`; `exported_job="<ref>-api"` → `{{EXPORTED_JOB}}` |
| `templates/grafana/dashboards/service-health.json.tmpl` | `deploy/grafana/dashboards/<ref>-service-health.json` | idem |
| `templates/grafana/dashboards/messaging.json.tmpl` | `deploy/grafana/dashboards/<ref>-messaging.json` | idem |
| `templates/grafana/dashboards/crons.json.tmpl` | `deploy/grafana/dashboards/<ref>-crons.json` | idem |
| `templates/grafana/dashboards/integration-errors.json.tmpl` | `deploy/grafana/dashboards/<ref>-integration-errors.json` | idem |

## Alertas

| Template | Arquivo-fonte de referência | Mudanças aplicadas |
|---|---|---|
| `templates/grafana/alerts/alert-rules.yaml.tmpl` | `deploy/grafana/alerts/<ref>-alert-rules.yaml` | prefixo de métricas → `{{SERVICE_NAME}}_*`; título → `{{SERVICE_PASCAL}}`; label `service:` → `{{SERVICE_NAME}}`; UIDs atualizados |

## O que NÃO está nos templates

Estes arquivos **não têm template equivalente** — implementam lógica de domínio exclusiva do serviço de referência:

- Métricas de domínio específico (ex: sync entre sistemas externos, splits de transações financeiras)
- Dashboards de fluxos de negócio proprietários
- Decorators e utilitários acoplados a abstrações internas (ex: decorator `RecordMetric` que depende de contexto do framework)
- Módulos de integração com sistemas externos específicos da organização

O template gera apenas o **chassi genérico**: counters e histograms para HTTP, PubSub, Cron e Integration. Cada serviço adiciona suas próprias métricas de domínio depois.

## Procedure de ressincronização

Quando um arquivo-fonte de referência mudar:

1. Abrir o arquivo modificado e o template correspondente lado a lado
2. Aplicar as mesmas mudanças no template, preservando os placeholders `{{SERVICE_*}}`
3. Testar rodando a Skill num serviço de teste com `service_name=testsvc`
4. Verificar que a substituição ainda funciona corretamente
