# Skill: `/obs-apply`

Aplica os arquivos gerados por `/obs-panel`, `/obs-alert` ou `/otel-bootstrap` em um Grafana real — o único ponto de escrita de todo o fluxo de observabilidade assistida.

## Por que é separada dos outros fluxos

Nenhum agent (`observability-analyst`, `observability-builder`) tem token de escrita. Só este script tem, e só ele é chamado com `--apply` para efetivamente escrever. Isso mantém o caminho de escrita isolado, auditável e sempre com confirmação explícita.

## O que a Skill faz

1. Sem `--apply` (padrão): valida os arquivos (`jq .`/`yq` + checagem de placeholders) e mostra exatamente o que seria feito — nenhuma chamada de escrita é feita.
2. Com `--apply`: aplica de fato.
   - **Painéis/dashboards** (`.json`) → `POST /api/dashboards/db`.
   - **Alertas** (`.yaml`/`.yml`) → `PUT /api/v1/provisioning/folder/:folderUid/rule-groups/:group`, resolvendo (ou criando) a pasta pelo título. O header `X-Disable-Provenance` **não** é enviado de propósito — assim as regras continuam somente-leitura na UI do Grafana e o git permanece fonte de verdade.

## Pré-requisitos

- [`yq`](https://github.com/mikefarah/yq) (`brew install yq`) — necessário só para aplicar arquivos de alerta (`.yaml`/`.yml`). Painéis (`.json`) usam apenas `jq`.
- `GRAFANA_URL` e `GRAFANA_ADMIN_TOKEN` preenchidos no `.env` da raiz do ai-dev-flow (`cp .env.example .env`, veja o [README principal](../../README.md#configuration-env)) — ou exportados no shell, como fallback. `apply.sh` carrega o `.env` automaticamente.
- `GRAFANA_ADMIN_TOKEN` é um **token diferente** de `GRAFANA_SERVICE_ACCOUNT_TOKEN` (usado pelos agents). Este precisa de permissão de escrita (Editor/Admin); o token dos agents continua Viewer. Nunca use o mesmo token para os dois papéis, e nunca coloque o token de escrita no mesmo lugar de onde os agents leem.

## Como usar

```bash
cd ~/projetos/fulfillment-svc
claude

# Dry-run (padrão) — só valida e mostra o plano
/obs-apply deploy/grafana/dashboards/fulfillment-golden-signals.json

# Aplica de fato, depois de revisar o diff
/obs-apply deploy/grafana/dashboards/fulfillment-golden-signals.json --apply
/obs-apply deploy/grafana/alerts/fulfillment-alert-rules.yaml --apply
```

## Importante

- **Teste primeiro contra um Grafana de homologação**, nunca produção na primeira execução — o mapeamento do YAML de alertas para a API de provisioning é best-effort (documentado no cabeçalho de `scripts/apply.sh`) e não foi validado contra uma instância real além do smoke test com mock incluído no desenvolvimento desta skill.
- Pastas (folders) do Grafana referenciadas no YAML são criadas automaticamente se não existirem — isso é aditivo, não destrutivo, mas ainda assim só ocorre com `--apply`.
