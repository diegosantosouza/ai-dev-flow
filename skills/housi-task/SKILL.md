---
name: housi-task
description: Cria uma tarefa no Jira da Housi (onhousi.atlassian.net) perguntando por espaço de trabalho, tipo de issue, sprint atual ou backlog, story points e vínculo com outra tarefa, em vez do usuário ter que redigitar o processo inteiro toda vez. Use sempre que o usuário pedir para criar uma tarefa, bug, história ou card no Jira, mencionar abrir um chamado para um trabalho que acabou de ser feito ou vai ser feito, ou disser algo como "abre uma tarefa pra isso" — mesmo sem dizer explicitamente "Jira" ou o nome de um espaço de trabalho.
argument-hint: "[resumo da tarefa] [--project SIGLA] [--parent CHAVE-123]"
allowed-tools: AskUserQuestion, mcp__claude_ai_Atlassian__getAccessibleAtlassianResources, mcp__claude_ai_Atlassian__getVisibleJiraProjects, mcp__claude_ai_Atlassian__getJiraProjectIssueTypesMetadata, mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql, mcp__claude_ai_Atlassian__lookupJiraAccountId, mcp__claude_ai_Atlassian__getIssueLinkTypes
---

# Criar tarefa no Jira

Full invocation as typed: **$ARGUMENTS**

O texto acima é o resumo da tarefa (tudo, não só a primeira palavra), mais quaisquer flags
`--project SIGLA` e `--parent CHAVE-123` que apareçam nele — leia o texto inteiro, não separe
por espaço às cegas. Se não vier nenhum resumo, peça um antes de continuar (não invente um).

Esta skill só cria a tarefa. Depois de criada, ela sugere a invocação de `/housi-ship` para
levar o código correspondente até os ambientes — as duas não são a mesma skill de propósito
(às vezes você só quer abrir a tarefa, sem ainda ter código pronto).

## Regras

1. **Nunca hardcode um único espaço de trabalho como se fosse o único que existe.** `APPSPACE`
   é o mais usado historicamente e deve aparecer sempre como primeira opção — recomendada — mas
   a lista de opções vem de `getVisibleJiraProjects` a cada invocação, e o "Other" que o
   `AskUserQuestion` já adiciona sozinho cobre qualquer projeto fora da lista mostrada.
2. **cloudId tem um único valor estável** (o site onhousi.atlassian.net) — descubra uma vez com
   `getAccessibleAtlassianResources` e não pergunte por ele.
3. **Os IDs de custom field (sprint, story points) são por-projeto e frágeis** — foram vistos
   mudando de instalação para instalação do Jira. Redescubra-os a cada invocação via
   `getJiraProjectIssueTypesMetadata`/consulta de campos do projeto escolhido; nunca hardcode
   `customfield_10020`/`customfield_10039` (esses IDs valem só para `APPSPACE` nesta instância,
   hoje — podem não valer para outro projeto ou mudar amanhã). Se um `createJiraIssue` falhar
   com 400 citando um customfield, trate como sinal para redescobrir o campo, não como erro fatal.
4. **Criar o issue é a única ação irreversível de verdade aqui.** Sempre mostre um resumo em
   texto (projeto, tipo, resumo, sprint/backlog, pontos, responsável, vínculo) e espere a
   confirmação normal de ferramenta antes de chamar `createJiraIssue`/`createIssueLink` — essas
   duas tools ficam de propósito fora de `allowed-tools`.
5. **Perguntas em duas chamadas de `AskUserQuestion`, não uma só.** A pergunta de projeto vem
   sozinha primeiro, porque a resposta dela determina que tipos de issue e que sprint existem
   para perguntar depois — e o limite da tool é 4 perguntas por chamada, então não cabem juntas
   de qualquer forma.

## Passos

### Passo 1 — Espaço de trabalho

Chame `getAccessibleAtlassianResources` (cacheie o cloudId mentalmente pelo resto da execução).
Chame `getVisibleJiraProjects` para esse cloudId. Pergunte com `AskUserQuestion`:

- header: `Projeto`
- pergunta: "Qual espaço de trabalho no Jira?"
- multiSelect: false
- opções: `APPSPACE (Recomendado)` primeiro, seguido de até mais 2-3 projetos retornados pela
  API (os que aparecerem primeiro na resposta, ou os mais recentes se a API expuser isso). Não
  liste todos os projetos existentes — o "Other" cobre o resto.

Se o usuário já tiver passado `--project SIGLA` no `$ARGUMENTS`, pule esta pergunta e use a
sigla informada diretamente (ainda valide que ela existe na lista de `getVisibleJiraProjects`;
se não existir, avise e caia na pergunta normal).

### Passo 2 — Descobrir tipos, sprint e campos do projeto escolhido

Com o projeto em mãos:

- `getJiraProjectIssueTypesMetadata` para os tipos de issue disponíveis (Bug, Tarefa, História,
  Epic, Subtarefa variam por projeto — não assuma que todos existem).
- `searchJiraIssuesUsingJql` com `project = <SIGLA> AND sprint in openSprints()` para achar a
  sprint ativa (nome + ID numérico do campo de sprint do board). Se não houver sprint ativa ou o
  projeto não usar sprints (Kanban puro), trate "backlog" como única opção e não pergunte sprint.
- Descubra o campo de story points do projeto (geralmente `customfield_XXXXX`, tipo número) via
  os metadados de campos do tipo de issue escolhido — pergunte o tipo primeiro (passo 3) se
  precisar do tipo para achar o campo certo.

### Passo 3 — Perguntas centrais

Uma chamada de `AskUserQuestion` com até 4 perguntas:

1. header `Tipo` — "Que tipo de issue?" — opções = tipos descobertos no Passo 2 (Bug primeiro
   se o pedido do usuário soar como correção de um problema; Tarefa primeiro caso contrário).
2. header `Destino` — "Sprint atual ou backlog?" — opções: `Sprint <N> (<nome>)` e `Backlog`.
   Se não há sprint ativa, pule esta pergunta e vá direto para backlog.
3. header `Pontos` — "Story points?" — opções: 1 / 2 / 3 / 5 (o "Other" cobre 8, 13, ou deixar
   vazio).
4. header `Responsável` — "Quem assume?" — opções: `Eu` (resolvido via `lookupJiraAccountId`
   com o e-mail do usuário atual) e `Ninguém` (não atribuído). "Other" cobre atribuir a outra
   pessoa por nome/e-mail.

### Passo 4 — Vínculo com outro issue (condicional)

Só pergunte isto se o usuário mencionou um issue relacionado no `$ARGUMENTS`, passou `--parent`,
ou o contexto da conversa deixar claro que esta tarefa nasce de/está ligada a outra já existente.
Chame `getIssueLinkTypes` e pergunte com `AskUserQuestion`:

- header `Vínculo` — "Linkar a outro issue?" — opções: `Não` / `Relates to` / `Blocks` /
  `Is blocked by` (ou os nomes reais que `getIssueLinkTypes` devolver, se diferentes).

Se a resposta não for "Não", peça a chave do issue relacionado se ainda não estiver clara.

### Passo 5 — Resumo e confirmação

Mostre um resumo em texto simples (não crie ainda):

```
Projeto: <SIGLA>
Tipo: <tipo>
Resumo: <título>
Destino: Sprint <N> / Backlog
Pontos: <N>
Responsável: <nome ou "não atribuído">
Vínculo: <tipo> com <CHAVE> (ou "nenhum")
```

Prossiga para `createJiraIssue` (e `createIssueLink`, se houver vínculo) — essas chamadas pedem
a confirmação normal de permissão de ferramenta, já que ficam fora de `allowed-tools`.

### Passo 6 — Encerramento

Ao terminar, informe a chave criada com o link (`https://onhousi.atlassian.net/browse/<CHAVE>`)
e imprima a linha de invocação pronta para a outra skill, por exemplo:

```
/housi-ship <CHAVE>
```

Não invoque `/housi-ship` automaticamente — só sugira a linha, para o usuário decidir quando
(e se) já há código pronto para seguir.
