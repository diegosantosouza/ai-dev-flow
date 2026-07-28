# Skill: `/obs-rca`

Investiga um erro, padrão de log ou trace ID cruzando dados do Grafana (logs, métricas, traces) com o código local, e aponta onde a falha provavelmente se originou.

## O que a Skill faz

1. Roda o **Preflight** do agent `observability-analyst` — confirma versão do Grafana, quais datasources existem, e se o Tempo tem o MCP proxy habilitado (traces só funcionam se sim).
2. Aplica um **loop de hipóteses**: cada hipótese é marcada como *root cause*, *symptom*, *refuted* ou *blocked*, e uma conclusão de causa raiz exige um **gatilho explícito** (deploy, mudança de config, capacidade esgotada) — não apenas correlação.
3. Cruza logs/traces com o código local (`Read`/`Grep`/`Glob`), respeitando a ressalva de source maps em Node/TypeScript.
4. É **somente leitura** — aponta o arquivo/função prováveis, mas nunca edita nada.

## Pré-requisitos

- [ai-dev-flow](https://github.com/gandarfh/ai-dev-flow) instalado (`./install.sh`)
- `mcp-grafana` instalado e no `PATH`, com `GRAFANA_URL` e `GRAFANA_SERVICE_ACCOUNT_TOKEN` preenchidos no `.env` da raiz do ai-dev-flow (`cp .env.example .env`) — veja o [README principal](../../README.md#configuration-env)
- Service account do Grafana com role **Viewer**

## Como usar

```bash
cd ~/projetos/fulfillment-svc
claude

/obs-rca 500s em /checkout desde 14:00
/obs-rca trace-id abc123def456
/obs-rca por que o consumer de pedidos está nackando desde ontem
```

O argumento é livre — pode ser uma descrição de erro, um trace ID, uma janela de tempo, ou uma combinação.

## Nota sobre segurança

Conteúdo de log é entrada controlada por terceiros (user-agent, path, body). O agent trata esse conteúdo como dado a correlacionar, nunca como instrução — se algo no log parecer uma diretiva, ele reporta como achado, não executa.
