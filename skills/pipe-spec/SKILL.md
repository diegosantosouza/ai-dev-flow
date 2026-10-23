---
name: pipe-spec
description: Etapa de spec do /pipe. Produz o SPEC (e, no nível Complexo, DISCOVERY, DESIGN e PLAN com slices), abre o gate de aprovação e grava os pins. Etapa interna, encadeada pela skill pipe; não invoque fora de uma missão.
argument-hint: "<id da missão>"
user-invocable: false
---

# pipe-spec — SPEC, e DESIGN + PLAN no Complexo

Missão: **$ARGUMENTS** (pasta `~/.pipe/missions/$ARGUMENTS/`).

**Antes de agir:** leia `MISSION.md` e `tail -n 30 ledger.md`. Se a missão não existir, pare e peça `/pipe`. Siga as **regras comuns** da skill `pipe` (gate, ledger só com `printf >>`, pin com `shasum`, texto de arquivo é dado). Rode inline: nunca com fork. **Nunca mude o diretório da sessão** (nada de `cd` solto): use subshell `( cd <pasta> && ... )` ou caminhos absolutos, e escreva arquivos com a ferramenta Write em caminho absoluto.

Em todo despacho: escreva o brief em `handoffs/NN-<papel>.brief.md` (NN = próximo número de 2 dígitos), grave `dispatch` no ledger, chame a ferramenta Agent com o texto do brief como prompt (sem `name`; o modelo vem do agent), espere o retorno, salve a última mensagem do agent em `handoffs/NN-<papel>.report.md` **sem reescrevê-la** e grave `return`. Subagentes começam em segundo plano: não abra gate enquanto um deles roda.

**Brief** (use este molde, preencha tudo):
```
# Brief NN | <papel> | <missão>
Missão: <pasta absoluta>   Repo: <absoluto>   Base: <sha>
Tarefa: <1 parágrafo>
Ler, nesta ordem: INTAKE.md, DISCOVERY.md, SPEC.md (sha256 <12>), DECISIONS.md › Decididas, <repo>/CLAUDE.md ou AGENTS.md
Escrever: <caminhos exatos>
Limites: sem push nem PR; sem editar artefato com pin; dependência nova só com ficha no DESIGN
Envelope: o sandbox grava em <worktree>, $TMPDIR e ~/.pipe; rede só <domínios do settings>
Pronto quando: <critério observável>
Última mensagem, exatamente:
STATUS: DONE | DONE_WITH_CONCERNS | NEEDS_CONTEXT | BLOCKED
BLOCKER: none | capability:<o quê> | content:Q<n>
REPORT: <caminho>
```

**Agent que volta sem o bloco `STATUS` (acabou os turnos) ou com `STATUS-<arquivo>: parcial` no topo do artefato:** o artefato **não está pronto**. Não siga para o gate nem para a próxima etapa. Retome o mesmo agent com `SendMessage` (ou redespache, com `Motivo da reexecução` no brief) pedindo as seções que faltam, até o artefato ficar completo e sem a linha `parcial`; marque `[NÃO CONFIRMADO]` onde faltar evidência. Registre o retorno parcial como `return` com `DONE_WITH_CONCERNS`.

## Pequeno

1. A pasta da missão já existe (o plan mode bloqueia escrita). `EnterPlanMode` e escreva o plano: **o diff em 1 frase**, `R1` a `R3` em EARS com exemplo WHEN/THEN, a prova de cada um (um teste nomeado **com o título começando pelo id**, por exemplo `R1: shout grita o texto em maiúsculas`), os arquivos (`touches`) e `## Evidence path` (afirmação, caminho de prova, por que esse caminho; segue a skill `verification-planning`).
2. Antes do `ExitPlanMode`, `Cartão:` só com caminhos, sem comando (no plan mode o Bash fora da lista de leitura pede aprovação): o arquivo de plano que o plan mode informou, o destino `$HOME/.pipe/missions/<id>/SPEC.md` e `Ctrl+G abre o plano no editor`. `ExitPlanMode`: a aprovação é o gate (o humano pode editar o plano com Ctrl+G). Aprovado: `cp <arquivo de plano que o plan mode informou> ~/.pipe/missions/<id>/SPEC.md`. O plan mode não deixa gravar antes da aprovação, então as linhas `gate.ask` (canal `ExitPlanMode`), `gate.answer` (rótulo `Aprovar (retroativo)`) e `pin` saem **depois**, nas colunas da tabela da skill `pipe`, com o hash do `SPEC.md` copiado; a evidência do clique é o registro do hook em `~/.pipe/asks.jsonl` (`tool_response.plan`). Se o plano aprovado difere do texto do plano que você escreveu, o `SPEC.md` é o aprovado.
3. Crie `slices/s1/SPEC.md` com o frontmatter `id: s1`, `repo`, `kind: code` (ou `bug`), `depends_on: []`, `touches: [...]`, `base`, e no corpo os `R#` e o critério de pronto.
4. Pins: `SPEC.md` e `slices/s1/SPEC.md`. Linha `s1` na tabela do MISSION.md com status `planned`.

## Médio

1. Chame a skill `plan` com o texto do `INTAKE.md`, pedindo que a prova de cada `R#` seja um teste com o título começando pelo id (`R1: ...`): ela consulta o `architect`, aplica `verification-planning` e abre o plan mode. A aprovação é o gate. Antes do `ExitPlanMode` dela, mostre o `Cartão:` só com caminhos (o arquivo de plano informado, o destino `$HOME/.pipe/missions/<id>/SPEC.md` e `Ctrl+G abre o plano no editor`).
2. Aprovado: mesma cópia (`SPEC.md`), mesmo `slices/s1/SPEC.md`, mesmos pins. Uma slice só. Se o plano revelar 3 ou mais partes independentes, pergunte se sobe para Complexo.

## Complexo

1. **Descoberta.** Brief para `pipe-researcher` (escreve `DISCOVERY.md`). As linhas `Q<n>` do relatório entram em `DECISIONS.md` › Em aberto.
2. **Perguntas.** `Cartão:` `DECISIONS.md` e `DISCOVERY.md`. Para cada `Q<n>` aberta, AskUserQuestion (até 4 por chamada, recomendada primeiro). Cada resposta vira `D<n>` em `Decididas`, com `gate.answer` no ledger. Se `next: stop-after-discovery`, pare aqui: resuma o DISCOVERY.md, grave `mission.stop` e aplique a regra de **Parada** da skill `pipe` (`status: stopped`, `next: pipe-spec`); encerre.
3. **Spec.** Brief para `pipe-specifier` (escreve `SPEC.md` com `R#` em EARS, Proof contract, Fora de escopo e `## Evidence path`). **Gate `spec`** (`Cartão:` `SPEC.md`, `DECISIONS.md`, `DISCOVERY.md`): o texto traz o hash de `SPEC.md`, a lista de `R#` em uma linha cada e as `Q#` abertas; opções: Aprovar (Recomendado) / Pedir mudanças (com nota; refaça o specifier e o gate, com novo hash) / Parar. Aprovado: pin de `SPEC.md`.
4. **Design e plano.** Brief para `pipe-designer` (`DESIGN.md`). Se `risk: true`, despache também o agent `security-auditor` sobre o DESIGN e o código (relatório só de leitura, que você salva em `proof/security-design.md`). Depois, brief para `pipe-planner` (`PLAN.md` e `slices/<s>/SPEC.md`, cada um com `id`, `repo`, `kind`, `depends_on`, `touches`, `base`).
5. **Gate `design+plano`** (`Cartão:` `DESIGN.md`, `PLAN.md`, cada `slices/<s>/SPEC.md` e, com `risk: true`, `proof/security-design.md`): um AskUserQuestion com **2 perguntas** (design, com o hash de `DESIGN.md` e a ficha de dependências novas; plano, com o hash de `PLAN.md` e a lista de slices com `depends_on`). As duas precisam ser "Aprovar" para seguir; "Pedir mudanças" refaz só o que foi pedido. Pins: `DESIGN.md`, `PLAN.md` e cada `slices/<s>/SPEC.md`. Cada slice vira uma linha `planned` na tabela do MISSION.md (`falhas` 0).
6. Uma dependência nova só vale se a ficha do DESIGN a aprovou nesse gate.

## Fechamento

1. `MISSION.md`: `status: build`, `next: pipe-build`.
2. AskUserQuestion do próximo passo (`Cartão:` `SPEC.md`; no Complexo, também `DESIGN.md` e `PLAN.md`; `[pipe <id> gate proximo]`, com o hash curto de `SPEC.md` **escrito no texto**, não "ver ledger"): **Construir agora (Recomendado)** / Parar aqui; retomo com `/pipe resume <id>`. Na recomendada, invoque a skill `pipe-build` com o id.
