# Skill: `/otel-bootstrap`

Automatiza o onboarding do padrão de observabilidade Housi (OpenTelemetry) em novos serviços Node.js/TypeScript ou Go.

## O que a Skill faz

1. **Detecta** automaticamente a linguagem e componentes do serviço alvo (HTTP, PubSub, Cron)
2. **Gera** a infraestrutura de tracer + métricas customizadas para a linguagem detectada
3. **Gera** dashboards Grafana e alert rules parametrizados com o nome do serviço
4. **Valida** que nenhum placeholder ficou sem substituição e que os JSONs são válidos

## Pré-requisitos

- Claude Code CLI instalado
- [ai-dev-flow](https://github.com/gandarfh/ai-dev-flow) instalado (`./install.sh`) — registra a Skill globalmente em `~/.claude/skills/`
- O serviço alvo deve ter `package.json` (Node) ou `go.mod` (Go) na raiz

## Como usar

Depois de instalar o ai-dev-flow, a Skill fica disponível globalmente. Basta navegar para o diretório do serviço alvo e executar:

```bash
cd ~/projetos/fulfillment-svc
claude

# Dentro da sessão Claude:
/otel-bootstrap fulfillment
```

O argumento é o **nome do serviço** (lowercase, sem espaços). Exemplos:
```
/otel-bootstrap fulfillment
/otel-bootstrap payment-gateway
/otel-bootstrap notifier
```

## O que é gerado

### Node.js/TypeScript

```
src/shared/tracer/
├── tracer.ts              # OTel SDK bootstrap (traces + metrics + logs via OTLP)
├── bootstrap.ts           # entry point: startTracer(SERVICE_NAME)
├── grpc-exporter.ts       # exportadores gRPC
├── http-exporter.ts       # exportadores HTTP
├── instrument-names.ts    # constantes de nomes de métricas (<service>.*)
├── attributes.ts          # constantes de atributos OTel (<SERVICE>_ATTR)
└── metrics/
    ├── base-metrics.ts    # classe abstrata BaseMetrics
    ├── integration-metrics.ts  # contador de erros em APIs externas
    ├── pubsub-metrics.ts  # [se PubSub] contador + histogram de mensagens
    └── cron-metrics.ts    # [se Cron] contador + histogram de execuções

src/consumers/
└── base.consumer.ts       # [se PubSub] base class com OTel spans + PubSubMetrics

src/crons/
└── base.cron.ts           # [se Cron] base class com OTel spans + CronMetrics
```

### Go

```
internal/otel/
├── tracer.go        # TracerProvider + MeterProvider via OTLP
├── bootstrap.go     # Init(ctx, serviceName) — chamado do main
├── metrics.go       # helpers para Counter/Histogram
├── http_middleware.go   # [se HTTP] otelhttp wrapper
├── pubsub_consumer.go   # [se PubSub] spans + métricas no Receive
└── cron.go              # [se Cron] spans + métricas no Run
```

> ⚠️ Templates Go são **v0.1**. Validar contra um serviço Go real antes de usar em produção.

### Grafana (sempre gerado)

```
deploy/grafana/
├── dashboards/
│   ├── <service>-golden-signals.json     # Latency / Traffic / Errors / Saturation
│   ├── <service>-service-health.json     # [se HTTP] visão geral on-call
│   ├── <service>-messaging.json          # [se PubSub] RED do Pub/Sub
│   ├── <service>-crons.json              # [se Cron] saúde dos jobs
│   └── <service>-integration-errors.json # erros em APIs externas
└── alerts/
    └── <service>-alert-rules.yaml        # HTTP 5xx, EL delay, nack rate, cron heartbeat
```

## Variáveis de ambiente necessárias (Node)

Adicionar ao secret de deploy do serviço:

```
OTEL_SERVICE_NAME=<service-name>
OTEL_EXPORTER=http                           # ou grpc
OTEL_EXPORTER_OTLP_ENDPOINT_HTTP=http://<collector>:4318
OTEL_SEMCONV_STABILITY_OPT_IN=http/dup       # opt-in semconv HTTP estável
EXPORT_INTERVAL=10000                         # ms, default 60000
```

## Importar dashboards no Grafana

Após a Skill gerar os arquivos:

1. Grafana → **Dashboards → New → Import**
2. Upload os JSONs de `deploy/grafana/dashboards/`
3. Selecione o datasource Prometheus
4. Importe `deploy/grafana/alerts/<service>-alert-rules.yaml` via **Alerting → Alert rules → Import**

## Manutenção

Os templates foram extraídos do **serviço de referência** — o primeiro serviço da organização a implementar o padrão OTel completo. Quando ele evoluir (ex: nova versão do SDK OTel), os templates em `skills/otel-bootstrap/templates/` precisam ser atualizados manualmente. Consulte `reference/template-sources.md` para a lista de pares template ↔ arquivo-fonte e o procedimento de ressincronização.

## Estrutura interna da Skill

```
skills/otel-bootstrap/
├── SKILL.md                    # playbook principal (lido pelo Claude)
├── README.md                   # este arquivo
├── templates/
│   ├── node/                   # templates Node.js/TypeScript
│   ├── go/                     # templates Go (v0.1)
│   └── grafana/                # templates dashboards + alerts
├── scripts/
│   ├── render.sh               # substituição de placeholders via sed
│   ├── detect.sh               # detecta linguagem + componentes
│   └── validate.sh             # valida JSONs e ausência de placeholders
└── reference/
    └── template-sources.md     # mapeamento template ↔ arquivo-fonte de referência
```
