status: superado por 2026-09-14-1750-handoff-0-6-1.md

# Handoff — a cerca encontra a sessão real — 2026-09-14 12:22

> Leia isto primeiro. Todo número aqui foi medido no ato, nesta sessão.

## Estado (medido agora)

| Repositório | Ramo | HEAD | Árvore | Versão | Remoto |
|---|---|---|---|---|---|
| `roadworthy` | `main` | `f51ad929b567` | limpa | 0.6.0 | sincronizado com `origin/main` |

| portão | resultado |
|---|---|
| `bash tests/run.sh` | 29 casos, 366 asserções, `RESULT: gate clean` |
| `bash tests/attack.sh` | 37 ataques, 32 recusados, 5 declarados |
| `docs-check.sh docs` · `pointers-check.sh README.md` | OK · OK |
| `refute-ledger.sh hooks --sources …` | 8 cercas, 0 sem registro |
| `claude plugin validate . --strict` | passou |
| `close.sh --check` | **6 de 6 FRESH** |

## A DIFERENÇA QUE MAIS IMPORTA AO RETOMAR

**A cópia instalada está atrás do repositório.** Ela é a 0.6.0 publicada em `a076e99`; o conserto
do portão de entrada entrou em `f51ad92`. Medido:

```
grep -c "inside=" ~/.claude/plugins/cache/roadworthy/roadworthy/0.6.0/hooks/rite-gate   # 0
```

Consequência viva enquanto isso não for refeito: **qualquer comando com `2>/dev/null` é negado**
nesta máquina, num projeto sem frente aberta. Para alinhar:

```
claude plugin update roadworthy@roadworthy
/reload-plugins
```

## A bancada de sete passos da 0.5.0 — o que rodou e o que não rodou

Rodou pela primeira vez contra a cópia **instalada**, que é a dívida que a 0.5.0 deixou aberta.

| # | passo | resultado medido |
|---|---|---|
| 1 | atualizar e recarregar; conferir a versão | **passou.** `claude plugin update` reportou `0.5.0 → 0.6.0`; `/reload-plugins` reportou 11 plugins; o diretório `0.6.0/` existe com `rite-gate` e `stop-gate` |
| 2 | com a trava declarada, escrever o arquivo de plano | **passou.** Escrita no plano em `plans_dir` permitida com `.roadworthy/scope` ativo (5 globs, nenhum em `plans_dir`) |
| 3 | escrever fora do escopo | **passou.** `Edit` em `README.md` negado com a mensagem literal do escopo, nomeando arquivo e caminho da trava; nada foi escrito |
| 4 | submeter plano sem seção de banca | **não rodou** — exige submissão em plan mode |
| 5 | submeter com `VERDICT: APPROVED` | **não rodou** — idem |
| 6 | submeter com `base:` que não resolve | **não rodou** — idem |
| 7 | `close.sh --check` num projeto sem portões | **passou.** Recusou com `no .roadworthy/gates — a closing with no declared gate is not a closing` |

Os três que faltam dependem de **uma** sessão em plan mode. Nada de código os bloqueia.

## O defeito que esta sessão expôs e NÃO consertou

**O `stop-gate` bloqueou um turno cujos portões estavam frescos.** Ele reportou os seis como
`MISSING` — não `STALE` —, e medido no minuto seguinte, `close.sh --check` da árvore de trabalho
**e** da cópia instalada devolveram os seis `FRESH`. `MISSING` é o sintoma de ter procurado noutro
registro de evidência: `close.sh` resolve o ledger por `ROADWORTHY_DATA`/`CLAUDE_PLUGIN_DATA`, e o
ambiente de um gancho não é o do shell (aqui as duas estão indefinidas e o ledger cai em
`.roadworthy/evidence.jsonl`, onde a evidência está).

Está no roteiro como pendência. **Não foi consertado de propósito:** consertar abriria a frente
seguinte, e o dono interrompeu exatamente esse laço.

## O que a sessão entregou, por caminho

- `tests/lib.sh`, `tests/cases.txt`, `tests/run.sh` (corredor), `tests/hooks/` (11 casos),
  `tests/scripts/` (14), `tests/meta/` (4, incluindo `runner.sh`), `tests/fixtures/` (5 construtores)
- `hooks/rite-gate` — escrita fora do repositório e o plano pelo shell
- `hooks/lib.sh`, `hooks/guard-commit` — os dois defeitos que a suíte de ataque achou
- `skills/plan/scripts/plan-preflight.sh`, `skills/plan/scripts/scope-write.sh --base`
- `CHANGELOG.md`, `README.md`, `docs/decisions/2026-09-14-0239-four-accepted-claims-refuted.md`

## Placar — o que esta sessão errou

| classe | o que foi |
|---|---|
| Confiar num mecanismo em vez de medi-lo | trava de concorrência escrita com `wait -n`, que não existe no bash 3.2 do macOS |
| Ler um verde como prova do que está ao lado | 26 de 28 casos "verdes" porque o harness engolia o aborto; quatro tinham morrido no meio |
| Editar por âncora sem reler o arquivo | o patch do `--check-manifest` não aplicou, e o auto-teste passou a chamar a suíte inteira |
| Continuar em vez de entregar a decisão | depois do reload, abri outra frente em vez de levar os três defeitos ao dono como achado da bancada. Foi o laço que ele interrompeu |

## Próximo passo concreto

1. `claude plugin update roadworthy@roadworthy` e `/reload-plugins` — alinhar a cópia instalada.
2. Uma sessão em plan mode para os passos 4, 5 e 6 da bancada.
3. Só então decidir sobre o `stop-gate` e sobre publicar de novo.

## Prompt para colar

```
Roadworthy: árvore limpa em f51ad92, sincronizado com origin, 6 portões FRESH, frente fechada.
Leia docs/plans/2026-09-14-1222-handoff-a-cerca-encontra-a-sessao-real.md ANTES de agir.
Duas coisas pendentes e ambas minhas: alinhar a cópia instalada (update + reload) e rodar os
passos 4, 5 e 6 da bancada numa sessão em plan mode. O defeito do stop-gate está no roteiro e
NÃO deve ser consertado sem eu mandar.
```
