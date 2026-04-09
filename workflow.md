# AI Agent Development Flow

Flow de desenvolvimento com Claude Code baseado em práticas reais documentadas
por Fabio Akita e guias de Context Engineering da Anthropic.

---

## 0. Setup: Ambiente Seguro

Antes de qualquer coisa, isole o agente de IA do seu sistema.

### Opções de Sandbox

| Ferramenta     | Plataforma  | Peso   |
| -------------- | ----------- | ------ |
| ai-jail        | Linux/macOS | Leve   |
| Dev Containers | Qualquer    | Pesado |
| Docker manual  | Qualquer    | Médio  |

### Camadas de Proteção (defense in depth)

1. **Sandbox do Claude Code** — permissões built-in
2. **ai-jail / container** — isolamento de OS
3. **Git** — rastreamento de toda mudança
4. **Backup** — snapshots regulares

### Instalação ai-jail

```bash
# Linux
cargo install ai-jail
# macOS — usa sandbox-exec nativo
```

---

## 1. Inicialização do Projeto

```bash
mkdir meu-projeto && cd meu-projeto
git init
```

### Criar CLAUDE.md

Copie o template e adapte:

```bash
cp /path/to/CLAUDE.md.template ./CLAUDE.md
```

Edite preenchendo:

- Stack tecnológica
- Convenções de código
- Regras de teste
- Foco atual

O CLAUDE.md é uma **especificação viva** — atualize-o conforme o projeto evolui.

---

## 2. Ciclo de Desenvolvimento: Research → Plan → Implement

### Fase 1: Research (Pesquisa)

**Objetivo**: Entender o problema antes de escrever qualquer código.

```
> Pesquise como [X funciona] neste projeto.
> Quais arquivos são afetados por [Y]?
> Mapeie o fluxo de dados de [A] até [B].
```

**Regras**:

- Use subagents para pesquisas exploratórias (preserva contexto principal)
- Revise os resultados — este é o ponto de maior alavancagem humana
- Se a pesquisa está fundamentalmente errada, reinicie com contexto limpo

### Fase 2: Plan (Planejamento)

**Objetivo**: Especificação detalhada antes da implementação.

```
> Crie um plano para implementar [feature].
> Liste os arquivos que serão criados/modificados.
> Defina a estratégia de testes.
```

**O plano deve conter**:

- Passos exatos de implementação
- Arquivos afetados
- Estratégia de verificação (testes)
- Riscos e edge cases

**Regras**:

- O humano revisa e aprova o plano antes de executar
- Itere no plano até estar satisfeito
- Um plano ruim gera milhares de linhas de código ruins

### Fase 3: Implement (Implementação)

**Objetivo**: Executar o plano aprovado.

```
> Implemente a fase 1 do plano.
> Rode os testes após cada mudança.
```

**Regras**:

- Execute fase por fase, não tudo de uma vez
- Teste após cada fase
- Compacte status de volta no plano para tasks complexas
- Mantenha contexto entre 40-60% — não encha a janela

---

## 3. Subagents (Agentes Especializados)

Subagents são agentes de IA especializados que rodam em contexto isolado.
Cada um tem seu próprio system prompt, ferramentas permitidas e modelo.

### Como funcionam

- São arquivos `.md` com frontmatter YAML
- `~/.claude/agents/` → disponível em todos os projetos
- `.claude/agents/` → específico do projeto (versionável no git)
- Claude decide quando delegar baseado na `description` do agent
- Você pode pedir explicitamente: "use o researcher para..."

### Agents configurados

| Agent | Modelo | Esforço | Permissões | Memória | Quando usar |
|-------|--------|---------|------------|---------|-------------|
| `architect` | opus | alto | Read-only + Web + Context7 | Sim (user) | Antes de implementar, pesquisar solução certa |
| `researcher` | haiku | baixo | Read-only | Sim (user) | Mapear codebase, arquivos e convenções |
| `test-runner` | haiku | baixo | Bash + Read (bypassPermissions) | Não | Rodar testes sem interrupção |
| `code-reviewer` | sonnet | médio | Read-only | Sim (user) | Revisar qualidade após mudanças |
| `debugger` | sonnet | alto | Read-only + Bash | Não | Diagnosticar bugs e root causes |
| `doc-writer` | haiku | baixo | Read + Write (acceptEdits) | Não | Criar/atualizar documentação |
| `committer` | haiku | baixo | Bash + Read (bypassPermissions) | Não | Criar commits descritivos |

> **Sessão principal usa `opusplan`**: opus durante `/plan` (decisões importam), sonnet durante `/implement` (execução).

### Anatomia de um subagent

```markdown
---
name: researcher
description: Quando usar este agent (Claude lê isso para decidir)
tools: Read, Grep, Glob, Bash       # Ferramentas permitidas
model: haiku                         # haiku | sonnet | opus | inherit
effort: low                          # high | medium | low — profundidade de raciocínio
maxTurns: 10                         # Limite de turnos antes de parar
memory: user                         # user | project | local
background: false                    # true = roda em paralelo
permissionMode: default              # default | acceptEdits | dontAsk | plan
hooks:                               # hooks específicos deste agent
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh"
---

System prompt do agent vai aqui em Markdown.
```

### Campos importantes

| Campo | O que faz |
|-------|-----------|
| `tools` | Allowlist — quais ferramentas o agent pode usar |
| `disallowedTools` | Denylist — ferramentas bloqueadas |
| `model` | Qual modelo LLM usa (controla custo e capacidade) |
| `memory` | Diretório persistente entre sessões (aprende ao longo do tempo) |
| `background` | Se `true`, roda em paralelo sem bloquear a conversa |
| `isolation: worktree` | Roda num git worktree isolado |
| `skills` | Skills pré-carregadas no contexto do agent |
| `hooks` | Hooks que rodam apenas enquanto este agent está ativo |
| `maxTurns` | Limite de turnos antes de parar |
| `effort` | Profundidade de raciocínio: `high` (pensa mais), `medium`, `low` (responde rápido) |

### Modelos e quando usar cada um

| Modelo | Custo | Velocidade | Use para |
|--------|-------|-----------|----------|
| **haiku** | Baixo | Rápido | Pesquisa, testes, buscas simples |
| **sonnet** | Médio | Médio | Code review, análise, implementação moderada |
| **opus** | Alto | Lento | Arquitetura, raciocínio complexo |
| **inherit** | (herda) | (herda) | Quando quer o mesmo modelo da sessão principal |

### Estratégia de custo por fase

A escolha de modelo para cada agent não é arbitrária:

- **opus → `architect`**: decisões arquiteturais são caras de desfazer. O custo do modelo é irrelevante comparado ao custo de reconstruir sobre fundação errada.
- **sonnet → `code-reviewer`, `debugger`**: trabalho analítico que se beneficia de raciocínio forte, sem precisar do peso total do opus.
- **haiku → `researcher`, `test-runner`, `doc-writer`, `committer`**: tarefas mecânicas onde velocidade importa mais que profundidade.
- **`opusplan` na sessão principal**: usa opus durante o planejamento (onde as decisões pesam mais) e troca para sonnet durante a execução.

| Fase | Agent | Custo |
|------|-------|-------|
| `/research` | `researcher` (haiku) | baixo |
| `/plan` | `architect` (opus) | alto — vale a pena |
| `/implement` | sessão principal (sonnet via opusplan) | médio |
| `/review` | `code-reviewer` (sonnet) | médio |
| `/commit` | `committer` (haiku) | baixo |

### Como criar novos agents

```bash
# Via interface interativa (recomendado)
/agents

# Ou crie o arquivo manualmente
~/.claude/agents/meu-agent.md

# Ou via CLI (temporário, só para a sessão)
claude --agents '{"meu-agent": {"description": "...", "prompt": "...", "model": "haiku"}}'
```

### Memória persistente

Agents com `memory: user` mantêm um diretório em `~/.claude/agent-memory/<nome>/`
que sobrevive entre sessões. Útil para:

- Acumular conhecimento sobre padrões do projeto
- Lembrar decisões arquiteturais
- Melhorar ao longo do tempo com experiência

---

## 4. Context Engineering

### Princípios

1. **Qualidade > Quantidade**: menor set de tokens com maior sinal
2. **Compactação frequente**: resuma, preserve decisões, descarte ruído
3. **Just-in-time**: busque info quando precisar, não carregue tudo upfront
4. **Hierarquia de prioridade**: info incorreta > info ausente > ruído

### Técnicas Práticas

#### Delegar a subagents

Output verboso (testes, logs, pesquisa extensa) fica isolado no contexto do
subagent. Apenas o resumo volta para a conversa principal.

#### Sessões focadas

- Uma sessão = uma feature ou fix
- Contexto limpo para cada unidade de trabalho
- Não tente resolver tudo numa sessão gigante

#### Documentos de contexto

```
docs/
├── architecture.md    # Decisões que não mudam toda hora
├── plan.md           # Plano atual (vive e morre com a feature)
└── research/         # Notas de pesquisa por tópico
```

---

## 5. Testes como Fundação

"1.323 testes em 8 dias" — Akita, The M.Akita Chronicles

### Regras

- **Todo código novo tem teste** — sem exceções
- **Rode testes antes de considerar "pronto"** — sempre
- **Testes crescem com o projeto** — 1.323 → 1.422 é normal e esperado
- **Testes permitem iteração com confiança** — este é o valor real

### Padrão

```bash
# Após cada implementação
> Rode os testes.
> Se falhar, corrija antes de avançar.
```

---

## 6. Pós-Deploy: Iteração Contínua

"Software 'done' não existe." — 125 commits pós-produção confirmam.

### O ciclo real

```
Deploy → Usuários reais → Casos não previstos → Fix/Evolve → Deploy → ...
```

### Expectativas corretas

- A implementação inicial é um **ponto de partida**, não o produto final
- Feedback real gera trabalho que nenhum planejamento prevê
- Cada iteração melhora a qualidade e a robustez
- O CLAUDE.md evolui junto com o projeto

---

## 7. Anti-Patterns (O que NÃO fazer)

| Anti-Pattern      | Por que é ruim                               |
| ----------------- | -------------------------------------------- |
| One-shot prompt   | Problemas complexos precisam de iteração     |
| Encher o contexto | Degrada qualidade do output progressivamente |
| Pular pesquisa    | Implementação sem entendimento = retrabalho  |
| Ignorar testes    | Impossível iterar com confiança              |
| Over-engineering  | Resolva o problema atual, não o imaginário   |
| Confiar cegamente | O humano é o arquiteto, a IA é o executor    |
| Rodar sem sandbox | Um comando errado pode destruir dados        |

---

## 8. Checklist de Sessão

```
[ ] Ambiente sandboxed e seguro
[ ] CLAUDE.md atualizado com foco atual
[ ] Pesquisa feita e revisada
[ ] Plano criado e aprovado
[ ] Implementação fase por fase
[ ] Testes passando após cada fase
[ ] Commit com mensagem descritiva
[ ] CLAUDE.md atualizado se necessário
```

---

## Fontes

- [Akita: Do Zero à Pós-Produção em 1 Semana](https://akitaonrails.com/2026/02/20/do-zero-a-pos-producao-em-1-semana-como-usar-ia-em-projetos-de-verdade-bastidores-do-the-m-akita-chronicles/)
- [Akita: Software Nunca Está Pronto](https://akitaonrails.com/2026/03/01/software-nunca-esta-pronto-4-projetos-a-vida-pos-deploy-e-por-que-one-shot-prompt-e-mito/)
- [Akita: AI Jail — Sandbox para Agentes de IA](https://akitaonrails.com/2026/03/01/ai-jail-sandbox-para-agentes-de-ia-de-shell-script-a-ferramenta-real/)
- [Anthropic: Effective Context Engineering for AI Agents](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
- [Advanced Context Engineering for Coding Agents](https://github.com/humanlayer/advanced-context-engineering-for-coding-agents)
