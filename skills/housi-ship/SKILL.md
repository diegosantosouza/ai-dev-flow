---
name: housi-ship
description: Abre a série de PRs de uma mudança já commitada para os ambientes de um repositório Housi (sandbox/homolog/produção), detectando em runtime a convenção de cada repo — nome das branches-base por ambiente, se o repo reusa uma branch para os N PRs ou cria uma nova por ambiente, e se a branch é apagada no merge — em vez de assumir um padrão fixo. Faz um dry-run do cherry-pick com git merge-tree antes de criar qualquer branch, roda os testes via subagent antes do push, e preenche o pull_request_template.md do repo em português com o link do Jira. Use sempre que o usuário falar em backport, "subir para homolog", "abrir PR para produção", "levar essa correção para os outros ambientes", ou mencionar uma chave de issue (ex. APPSPACE-123) junto com deploy/PR — mesmo que não diga a palavra "backport".
argument-hint: "[CHAVE-123] [--from <sha>] [--env sandbox,homolog,prod]"
allowed-tools: AskUserQuestion, Read, Grep, Glob, Task, Bash(bash ${CLAUDE_SKILL_DIR}/scripts/repo-facts.sh *), Bash(git fetch *), Bash(git merge-tree *), Bash(git log *), Bash(git status *), Bash(git branch *), Bash(gh pr list *), Bash(gh repo view *)
---

# Backport / abertura de PRs multi-ambiente

Full invocation as typed: **$ARGUMENTS**

O texto acima pode trazer a chave do Jira, `--from <sha>` (o commit a cherry-pickar; se
ausente, use o HEAD atual ou o commit que o usuário acabou de descrever na conversa) e
`--env sandbox,homolog,prod` (se ausente, pergunte). Rode a partir do repositório que o usuário
quer levar adiante — se não estiver claro qual repo, pergunte antes de tudo.

Esta skill **não implementa código** — ela leva algo que já existe (um commit, uma branch local)
até os ambientes via PR. Se o usuário ainda não tem o código pronto, pare e sugira `/plan` (o
processo Research → Plan → Implement já estabelecido) em vez de tentar escrever a mudança aqui.

## Regras

1. **Cherry-pick, nunca reimplementar.** O commit já existe; a única exceção é resolver um
   conflito real apontado pelo dry-run do passo 3.
2. **`gh pr create` sempre com `--base` explícito.** Nunca confie no default branch do repo —
   já existe pelo menos um repo Housi (`site-nextjs`) cujo default é `homolog`, não `main`.
3. **Se `delete_branch_on_merge` for `true`, repushar a branch antes de cada PR seguinte.** Ela
   pode ter sido apagada automaticamente pelo merge do PR anterior — um `git push` que "não
   muda nada" nesse caso na real está recriando a branch.
4. **Dry-run com `git merge-tree` antes de criar qualquer branch**, para cada ambiente
   selecionado — nunca só `git diff --stat` entre as bases (isso mostra divergência que não tem
   nada a ver com o cherry-pick em si; `merge-tree` modela o merge de verdade).
5. **Testes via subagent (`test-runner` ou equivalente), nunca rodados inline** — mantém o
   output verboso fora do contexto principal.
6. **Resumo + confirmação antes do primeiro `git push` de cada ambiente e antes de cada
   `gh pr create`** — são as duas ações com efeito colateral real (reescrevem o remoto / criam
   um PR público), ficam de propósito fora de `allowed-tools`. O mesmo vale para
   `git checkout -b` e `git cherry-pick`.
7. **Nunca hardcode o mapa ambiente→branch nem o estilo de PR** — sempre vêm de
   `scripts/repo-facts.sh`, rodado de novo a cada invocação (o repo pode ter mudado desde a
   última vez).
8. **v1 só cobre fan-out por cherry-pick** (branch nova ou reaproveitada, cherry-pick, PR — um
   por ambiente). Uma "cadeia de promoção" (merge sequencial ambiente-a-ambiente, ex.
   `develop`→`homolog`→`main`) reduziria a divergência entre branches, mas muda o fluxo de
   trabalho atual do time — não está implementada aqui. Se o usuário pedir esse modo
   explicitamente, diga que ainda não existe nesta skill em vez de simular com merges soltos.
9. **Nunca use `git checkout <branch-ou-commit> -- <path>` para só "espiar" o conteúdo de outra
   branch.** Esse comando não troca de branch — ele sobrescreve o working tree da branch **atual**
   com o conteúdo daquele path na outra branch, apagando qualquer edição não commitada na branch
   atual para esses arquivos, sem aviso e sem stash automático. Já aconteceu de verdade num
   test-drive desta skill: um `git checkout main -- .` rodado "só para conferir" enquanto a branch
   nova já estava com working tree sujo apagou 4 arquivos de trabalho não commitado. Para inspecionar
   o conteúdo de outra branch sem mexer no working tree atual, use `git show <branch>:<path>` (ou
   `git diff <branch> -- <path>`). Nunca rode `git checkout <ref> -- .`/`<ref> -- <path>` quando
   `git status` mostrar qualquer coisa não commitada nesses paths na branch atual.

## Passos

### Passo 0 — Detectar a convenção deste repositório

`git fetch origin`, depois rode `bash ${CLAUDE_SKILL_DIR}/scripts/repo-facts.sh` no diretório do
repo. **Mostre o que foi detectado antes de perguntar qualquer coisa**: lista de ambientes
(ambiente + branch-base + de onde veio), `delete_branch_on_merge`, `branch_style` e a evidência,
e se há `pr_template`.

Interprete `branch_style`:

- `"shared"` → recomendar reaproveitar a MESMA branch para os N PRs (como `site-nextjs`).
- `"per-environment"` → recomendar criar uma branch nova por ambiente, com sufixo
  `-<ambiente-detectado>` (ex. `-develop`, `-homolog`, `-main`, usando o nome real da branch-base
  de cada ambiente, não uma palavra genérica).
- `"mixed"` → **os dois padrões coexistem neste repo** (ex. branches de promoção antigas ao lado
  do padrão por-ambiente mais recente). Recomende o que tiver **mais entradas de evidência**, mas
  pergunte para confirmar em vez de decidir sozinho.
- `"unknown"` (poucos/nenhum PR mergeado para aprender, ou nenhum ambiente detectado em
  `.github/workflows/`) → pergunte diretamente ao usuário quais branches-base usar e qual estilo,
  não assuma nada.

Se `environments` vier vazio, **não assuma** `develop`/`homolog`/`main` — pergunte as
branches-base reais (pode ser um repo sem GitHub Actions, ou com nomes de workflow fora do
padrão que o script reconhece).

### Passo 0.5 — Checar o estado do working tree

Rode `git status --short --branch`. Se houver qualquer coisa modificada/não rastreada **e** a
branch atual for uma das branches-base detectadas no Passo 0 (ex. `main`, `develop`) — ou seja,
o usuário trabalhou direto numa branch compartilhada, sem abrir uma branch de trabalho — não
prossiga com cherry-pick nem com as perguntas do Passo 2 assumindo que já existe um commit.
Trate como uma variante da opção "Já está na branch atual" do Passo 2: explique a situação,
proponha criar uma branch nova a partir da base do primeiro ambiente escolhido e commitar as
mudanças lá (nunca commitar nem dar push direto na branch-base), e só então seguir para os
Passos 3-5 a partir desse commit novo. Mostre o resumo do que será commitado (arquivos
modificados/novos) antes de commitar.

### Passo 1 — Resolver a chave do Jira

De `$ARGUMENTS`, ou do nome da branch atual (padrão tipo `SIGLA-123`). Se não achar, pergunte.

### Passo 2 — Perguntas centrais

Uma chamada de `AskUserQuestion` com até 4 perguntas (pule as que já vieram resolvidas por flag
ou pelo Passo 0):

1. header `Origem` — "De onde vem a mudança?" — opções: `Cherry-pick de commit existente` /
   `Já está na branch atual` / `Ainda preciso implementar` (se esta última, pare e aponte para
   `/plan` — ver Regra 0 acima, não é código-fonte desta skill). Se o Passo 0.5 já detectou
   mudanças não commitadas numa branch-base, pule esta pergunta — a origem já está resolvida
   (vai virar commit novo numa branch nova).
2. header `Ambientes` — "Para quais ambientes abrir PR?" (multiSelect) — opções geradas a partir
   da lista de `environments` do Passo 0, com a branch real no label (ex. "Sandbox (develop)"),
   nunca "sandbox/homolog/produção" genérico. Se o script detectou mais de 4 ambientes, mostre os
   4 mais prováveis (sandbox/dev primeiro, produção por último) e trate o resto como uma segunda
   pergunta só se o usuário pedir "outro". Se `environments` veio vazio, troque esta pergunta por
   texto livre pedindo as branches-base.
3. header `Ordem` — "Abrir todos agora ou em etapas?" — opções: `Todos agora` / `Só o primeiro,
   valido e volto`.
4. header `Testes` — "Rodar os testes antes do push?" — opções: `Sim, via subagent` / `Já
   rodei, pular` (default "Sim" — testes antes de push fazem parte do fluxo já estabelecido).

Se `branch_style` foi `"mixed"`, faça uma chamada extra (antes ou junto, se sobrar espaço nas 4
perguntas) perguntando qual estilo usar desta vez, mostrando as duas evidências.

### Passo 3 — Dry-run por ambiente

Para cada ambiente selecionado, ANTES de criar qualquer branch:

```
git merge-tree --write-tree --merge-base=<commit>^ <branch-base-do-ambiente> <commit>
```

Exit 0 = aplica limpo. Exit 1 = lista os caminhos em conflito — nesse caso, chamada de
`AskUserQuestion` (header `Conflito`): "O cherry-pick em `<base>` conflita em `<N>` arquivo(s).
O que fazer?" com opções `Resolver agora (cherry-pick manual)` / `Pular esse ambiente` / `Usar
outra base`.

### Passo 4 — Branch, cherry-pick, testes, push (por ambiente, na ordem escolhida)

1. Nome da branch conforme o `branch_style` (Passo 0): reaproveitar a mesma em todos os
   ambientes (`"shared"`), ou criar `<prefixo>/<CHAVE>-<slug>-<ambiente>` nova por ambiente
   (`"per-environment"`) — prefixo (`fix/`, `feat/`, ...) herdado do tipo do commit convencional
   sendo cherry-pickado, slug derivado do resumo do commit.
2. `git checkout -b <branch> <branch-base-do-ambiente>` (pede confirmação — fora de
   `allowed-tools`).
3. `git cherry-pick <commit>` (idem). Se conflitar apesar do dry-run limpo (raro, pode ter havido
   push novo na base entretanto), pare e avise — não force resolução automática.
4. Se a resposta do Passo 2 pediu testes: delegar a um subagent `test-runner` (via `Task`) para
   rodar a suíte do repo nessa branch; reportar só o resultado, não o output completo.
5. `git push -u origin <branch>` (pede confirmação). Se `delete_branch_on_merge` é `true` e esta
   NÃO é a primeira branch da sequência (a de um ambiente anterior já foi mergeada e pode ter
   sido apagada), refaça o push antes deste passo se o branch não existir mais no remoto.

### Passo 5 — Abrir o PR

`gh pr create --base <branch-base-do-ambiente> --head <branch>` (pede confirmação). Título e
corpo em português; se `pr_template` existir, preencher as seções dele (não inventar um formato
próprio); sempre incluir o link `https://onhousi.atlassian.net/browse/<CHAVE>` e um resumo do
que mudou. Se a ordem escolhida no Passo 2 foi "só o primeiro, valido e volto", pare aqui e
espere o usuário retomar.

### Passo 6 — Encerramento

Resumir os PRs abertos (número + URL) por ambiente.
