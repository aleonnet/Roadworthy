status: accepted

# Handoff — a bancada da 0.7.1 em sessão interativa — 2026-10-01 20:13

> Leia isto primeiro. Supera `2026-10-01-1807-handoff-0-7-1.md`. Todo número vem com o comando
> rodado no ato, nesta máquina, em 2026-10-01. Este arquivo é escrito e commitado ANTES do fecho;
> a prova do fecho fica no livro de evidências (`.roadworthy/evidence.jsonl`), e o que vem depois
> dele (push, CI) está no fim, marcado como não medido aqui.

## Estado (medido no ato, antes do commit)

- Ramo `main`, base da frente `f8556d6`. `git rev-list --left-right --count origin/main...main`
  → `0 0` antes do commit desta frente.
- 0.7.1 publicada e instalada: a CI do push de `f8556d6` (execução 36929374259) terminou
  `success` nos três jobs; `claude plugin update roadworthy@roadworthy` levou a cópia instalada
  de 0.7.0 para 0.7.1; `claude plugin details roadworthy@roadworthy` →
  `Roadworthy (roadworthy) 0.7.1`.
- Frente aberta de `2026-10-01-1947-bancada-da-0-7-1.md`, aprovada uma vez, dez portões, só
  documentos.

## O que a bancada mostrou

Os três itens que só se provavam com a versão carregada numa sessão interativa foram vistos, os
três confirmados. O registro completo, com comando e saída de cada um, é
`docs/decisions/2026-10-01-1947-bancada-da-0-7-1.md`.

| Item | O que se viu | Onde está a prova |
|---|---|---|
| O veredito de um revisor real fica anotado | um registro às 19:47:13: `APPROVED`, com o nome do revisor, vindo pela entrega por ferramenta, sem duplicata; antes eram zero em quatro leituras | registros `review` do livro de evidências |
| O dono responde uma verificação humana no próprio prompt | pedido às 19:47:04, resposta às 20:13:09 com `by: the owner, in the prompt`; o estado saiu de `needs_human` para `passed` | registros `needs-human` e `human`, mesmo id `516896ed` |
| A aprovação de um plano fica anotada na hora | um registro às 20:04:56 gravado pelo gancho, lido antes de abrir a frente; antes eram quatro, todos pelo caminho de reserva; a frente abriu dele | registros `approval`; a impressão digital do retrato da frente é a mesma |

## Abertos — nenhum é pendência da 0.7.1; os três primeiros são achados sem frente

1. **Sem um `python3` que rode, toda cerca deixa a chamada passar.** A própria negação é escrita
   por ele. Igual na 0.7.0. Conserto pequeno (uma negação de reserva escrita sem `python3`), em
   `hooks/lib.sh`, que todo gancho carrega: pede frente própria.
2. **O registro da aprovação traz o nome do arquivo do modo de plano**, não o do plano em
   `docs/plans/`. A frente abre certo, pela impressão digital; quem lê o livro à mão não sabe
   qual plano foi.
3. **O pré-voo de um plano novo, com a frente anterior já fechada, lê a base dessa frente
   anterior.** Um plano que cite linhas de arquivo seria conferido contra um commit antigo.
   Medido uma vez (`plan-preflight (before the work, base 3ed9aab142be)` com o topo em
   `f8556d6`); não investigado além disso.
4. O runbook existe só em inglês (dispensado pelo dono em 2026-10-01).
5. Os três limites declarados da 0.7.0 seguem como estavam; o redesenho que os fecha continua sem
   plano aprovado.

## Onde o estado real mora

- `docs/decisions/2026-10-01-1947-bancada-da-0-7-1.md` — o registro da bancada.
- `docs/plans/done/2026-10-01-1807-handoff-0-7-1.md` — o handoff da 0.7.1: o que cada conserto
  faz, as provas, as duas leituras frias e o placar dos meus erros.
- `CHANGELOG.md`, seção `[0.7.1]` — a subseção "Not yet seen in a real interactive session" foi
  respondida pelo registro acima; a seção é histórica e não foi reescrita.

## Placar — o que esta frente errou no caminho

Nenhum erro medido: a frente é só de documento, o plano foi aprovado na primeira submissão e o
pré-voo passou na primeira rodada.

## Próximo passo concreto

1. `bash skills/close/scripts/close.sh` sobre o commit que leva este arquivo → `close: passed`,
   dez portões.
2. `git push` (toque do dono na YubiKey) → `gh run list --limit 3` verde nos três jobs.
3. Decisão do dono: se os achados 1 a 3 acima viram frente, e em que ordem.

## Prompt para colar

```
Roadworthy: leia docs/plans/2026-10-01-2013-handoff-bancada-da-0-7-1.md ANTES de agir. Confira
no ato: git status, git rev-list --left-right --count origin/main...main, close.sh --state,
gh run list --limit 3, claude plugin details roadworthy@roadworthy. A 0.7.1 está publicada,
instalada e vista em sessão interativa. Abertos, sem frente: a cerca que deixa passar sem
python3, o nome do plano no registro de aprovação, e a base que o pré-voo lê depois de uma
frente fechada.
```

Se o fecho, o push ou a CI tiverem falhado, cole o erro literal junto.

## Painel de fechamento — 2026-10-01 20:13 (antes do `close.sh`)

1. **O que mudou para o dono:** a 0.7.1 foi vista funcionando na sessão dele — a revisão
   independente, a aprovação de plano e a resposta humana deixam registro pelo caminho real.
2. **Entregue, por caminho:** `docs/decisions/2026-10-01-1947-bancada-da-0-7-1.md`; o plano e o
   handoff das 18:07 em `docs/plans/done/` com linha no índice; `.roadworthy/gates`; este handoff.
3. **Próximo a entregar e o que consome deste:** o fecho consome o commit; o push consome o
   fecho.
4. **Prova:** a tabela acima e o registro de decisão.
5. **Dentro da tolerância?** Sim.
6. **Números antes → depois:** registros de revisão no livro 0 → 1; aprovações gravadas na hora
   0 de 4 → 1 de 5; verificações humanas respondidas pelo prompt do dono 0 → 1.
7. **Acervo tocado:** criados: o registro de decisão e este handoff; movidos para `done/`: o
   plano da bancada e o handoff das 18:07; apagado: nada.
8. **Limite ainda aberto:** os cinco itens de "Abertos"; a CI deste push.
9. **Decisão do dono:** o toque na YubiKey no push; o destino dos três achados.
