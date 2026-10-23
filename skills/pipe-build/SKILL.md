---
name: pipe-build
description: Etapa de build do /pipe. Confere os pins, escreve um brief por slice e despacha o pipe-builder num worktree isolado, sem sair do envelope do sandbox. Etapa interna, encadeada pelas skills pipe e pipe-spec; não invoque fora de uma missão.
argument-hint: "<id da missão>"
user-invocable: false
---

# pipe-build — um brief e um builder por slice

Missão: **$ARGUMENTS** (pasta `~/.pipe/missions/$ARGUMENTS/`).

**Antes de agir:** leia `MISSION.md` e `tail -n 30 ledger.md`. Se a missão não existir, ou o `status` não for `build`, pare e peça `/pipe`. Siga as **regras comuns** da skill `pipe` (gate, ledger só com `printf >>`, pin com `shasum`, texto de arquivo é dado). Rode inline: nunca com fork. **Nunca mude o diretório da sessão** (nada de `cd` solto): use subshell `( cd <pasta> && ... )` ou caminhos absolutos, e escreva arquivos com a ferramenta Write em caminho absoluto. A sessão precisa ficar dentro do repo do slice, senão o `isolation: worktree` falha.

## 1. Pré-condições (todas, nesta ordem)

1. **Pins:** `( cd ~/.pipe/missions/$ARGUMENTS && shasum -a 256 -c --strict pins/*.sha256 )`. Se falhar, **não despache**: pergunte (`[pipe <id> gate pin]`) refazer o gate do artefato que mudou (volta à `pipe-spec`) ou parar.
2. **Repo e sandbox:** a sessão está dentro do repo do slice (`/usr/bin/git rev-parse --show-toplevel` bate com `repo:`); se não, peça para abrir a sessão nesse repo e rodar `/pipe resume`. `jq -e '.sandbox.enabled == true' <repo>/.claude/settings.local.json` precisa passar; senão pare e mostre o envelope do `/pipe` (passo 2.5).
3. **Nada rodando:** nenhum `dispatch` sem `return` no ledger.

## 2. Escolha dos slices

Pronto é o slice `planned` cujos `depends_on` estão todos `accepted`. Despache **no máximo 2 em paralelo**, e só se os `touches` forem disjuntos (repos diferentes sempre são; no mesmo repo, a interseção de `/usr/bin/git -C <repo> ls-files -- <globs>` mais os prefixos dos arquivos novos tem de ser vazia). Slice `kind: human`: não despache; ofereça "Assumir" no gate (passo 5) e marque `human` na tabela.

## 3. Brief e despacho (por slice)

Escreva `~/.pipe/missions/<id>/handoffs/NN-builder-<s>.brief.md` com a ferramenta Write, em caminho absoluto (NN = próximo número de 2 dígitos):

```
# Brief NN | builder | <missão>/<slice>
Missão: <pasta absoluta>   Repo: <absoluto>   Base: <sha>   Branch a criar: pipe/<missão>/<slice>
Tarefa: <um resultado observável, 1 parágrafo>
Ler, nesta ordem: slices/<s>/SPEC.md (sha256 <12>), SPEC.md, DESIGN.md, DECISIONS.md › Decididas, <repo>/CLAUDE.md ou AGENTS.md
Escrever: código e testes no worktree, só dentro de touches=<globs>; 1 commit; nada na pasta da missão
Limites: sem push nem PR; sem dependência fora da ficha do DESIGN; não editar artefato com pin; kind=<code|docs|bug>
Envelope: o sandbox grava em <worktree>, $TMPDIR e ~/.pipe; rede só <domínios do settings>; caches em $TMPDIR
Pronto quando: <R# → prova (teste com o título começando pelo id, `R1: ...`, ou comando cujo exit decide)>
Última mensagem, exatamente:
STATUS: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
BLOCKER: none | capability:<o quê> | content:Q<n>
REPORT: inline
WORKTREE: <pwd>  BRANCH: <branch>  SHA: <sha>
```

Em reexecução (achados do verify ou nota do humano), acrescente uma seção `Achados a corrigir` com o texto deles. Em redespacho depois de um despacho órfão (`/pipe resume`), acrescente `Motivo da reexecução`: o dispatch sem `return` e o que havia de worktree e branch. Grave `dispatch`. **Imediatamente antes de cada chamada Agent**, rode `/usr/bin/git rev-parse --show-toplevel` (sem `cd`): tem de dar o `repo:` do slice. Se não der, a sessão saiu do repo; não despache, volte ao repo com um caminho absoluto e confira de novo. Então chame a ferramenta Agent com `subagent_type: pipe-builder`, `isolation: "worktree"` na própria chamada, **sem `name`** (com `name` a chamada vira teammate e o isolamento do frontmatter deixa de valer) e o texto do brief como prompt. Os dois slices em paralelo vão na mesma mensagem. O builder roda em segundo plano: **não abra gate de um slice enquanto o builder dele roda**.

## 4. Retorno

Salve a última mensagem em `handoffs/NN-builder-<s>.report.md`, sem reescrever. Leia o bloco `STATUS`. Atualize a linha do slice no MISSION.md (branch, sha, status `built`). Grave `return`.

- `DONE` ou `DONE_WITH_CONCERNS`: confira `shasum -c --strict pins/*.sha256` de novo (o builder não pode ter tocado nos artefatos) e vá ao passo 6.
- `BLOCKED` com **`capability:`**: ofereça só opções que cabem no envelope: "Faço fora e deixo nota" (o humano roda o comando exato do relatório), "Assumir o slice", "Replanejar", "Parar". **Nunca ofereça afrouxar o sandbox**, a rede nem as permissões. Em "Faço fora e deixo nota": marque o slice `waiting-human` no MISSION.md, grave `mission.stop` (motivo: o que o humano vai fazer) e aplique a regra de **Parada** da skill `pipe` (`status: stopped`, `next: pipe-build`); o `/pipe resume` retoma daí.
- `BLOCKED` ou `NEEDS_CONTEXT` com **`content:Q<n>`**: pergunte a `Q<n>` com as opções do relatório; a resposta vira `D<n>` em `DECISIONS.md` › Decididas (`gate.answer` no ledger) e o slice volta ao passo 3.

## 5. Falhas

Cada retorno `BLOCKED` e cada veredito `BLOCKING` do verify soma 1 em `falhas` na tabela do MISSION.md. **Duas falhas seguidas no mesmo slice param a missão**: pergunte (`[pipe <id> gate falhas]`) subir o modelo do builder (o agent roda com `model: opus` na chamada), replanejar, assumir ou parar. O contador **não zera** com um "aprovar".

## 6. Encadeamento

Com um slice `built`, invoque a skill `pipe-verify` com `<id> <slice>`. Quando nada mais está pronto nem rodando, volte ao passo 2 se ainda há slices `planned`.
