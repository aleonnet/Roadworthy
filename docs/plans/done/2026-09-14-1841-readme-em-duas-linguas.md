# README em duas línguas, com TL;DR e divulgação progressiva

project: ~/Development/roadworthy
status: accepted

## Contexto

O dono perguntou se toda a documentação está atualizada e pediu: revisar o README, gerar a versão
em português do Brasil chaveável para o inglês, usar TL;DR e divulgação progressiva (o essencial
chamativo no topo, o detalhe dobrado abaixo), e fazer commit e push.

A auditoria desta sessão leu inteiros: `README.md`, `CHANGELOG.md`, `docs/README.md`,
`docs/reference/roadmap.md`, os cinco `SKILL.md`, `agents/cold-reviewer.md`, `evals/README.md`,
`evals-round2/README.md`, `hooks/hooks.json`, os dois manifests, o handoff vivo e o `PRINCIPLES.md`.
O que está desatualizado, medido no ato:

1. `README.md` diz "The four guards fail closed"; há SEIS cercas com `RW_ON_CRASH=deny`.
2. `README.md` diz "about 468 tokens always on, 220 to 530 per skill"; `claude plugin details`
   mede ~772 sempre ligados e 310 a 3,7 mil por invocação.
3. `hooks/hooks.json` diz "exit 2 is never used"; o `stop-gate` sai com 2, por contrato do evento
   Stop (o próprio README já declara a exceção).
4. O handoff vivo (`2026-09-14-1750`) lista como "ainda aberto" quatro itens já feitos: push, CI,
   atualização do plugin e desfazer dos links do Docker. Norma da casa: revisar é arquivo novo.

Tudo o mais (CHANGELOG, roteiro, skills, evals, mapa) está coerente com a árvore.

## Faixa de risco

**mínima**: documentação e uma string descritiva em JSON; suíte verde e validação do manifesto.

## Varredura de impacto (comandos rodados agora)
```
git grep -n 'four guards\|468 tokens\|exit 2 is never used'      # 3 ocorrências: README.md:37, README.md:55, hooks/hooks.json:2
grep -n 'RW_ON_CRASH' hooks/*                                     # deny em 6 cercas; allow em principles; warn em stop-gate
claude plugin details roadworthy@roadworthy                       # Always-on ~772 tok; on-invoke 310 a 3.7k
git grep -n 'README'                                              # nenhum teste lê o TEXTO do README; só pointers-check lê os caminhos citados
bash tests/attack.sh                                              # REFUSED=50 DECLARED=14 GREW=0 (64 ataques)
gh run list --limit 3                                             # run de 531f8f3: success (macos, ubuntu, windows-no-bash)
find ~/.docker -type l | wc -l                                    # 37 links de volta, igual ao arquivo de alvos do desfazer
```

## Mudanças, por arquivo

- `README.md` — reescrito com divulgação progressiva: linha de troca de idioma no topo, TL;DR de
  quatro pontos, instalação, a primeira frente em quatro passos, tabela das cercas com uma linha
  por garantia e o texto longo dobrado em `<details>`; o mesmo para skills e testes. Nenhuma
  afirmação medida é perdida: o texto atual migra para os blocos dobrados, com as duas frases
  desatualizadas corrigidas (seis cercas; ~772 tokens).
- `README.pt-BR.md` — NOVO: tradução integral do README, mesma estrutura de seções e de blocos
  `<details>`, mesma linha de troca de idioma apontando para `README.md`. Chaveamento é o padrão
  do GitHub: link cruzado no topo de cada arquivo (o GitHub não executa script em README).
- `hooks/hooks.json` — só a string `description`: a exceção do `stop-gate` (exit 2 é o contrato do
  evento Stop). Nenhuma chave de hook muda.
- `CHANGELOG.md` — seção `[Unreleased]` ganha "Changed": README em duas línguas, as duas correções
  e a descrição do `hooks.json`.
- `docs/plans/2026-09-14-1750-handoff-0-6-1.md` — só a primeira linha: `status: superado por
  <handoff novo>`.
- `docs/plans/<novo handoff>` — NOVO: estado medido hoje (push feito, CI verde, plugin 0.6.1
  instalado, 37 links do Docker de volta) e o painel de fechamento desta frente.
- `docs/plans/done/README.md` — uma linha de índice para este plano, movido para `done/` ao fechar.

## Escopo
Os globs que `scope-lock` vai impor, lidos deste bloco por `skills/plan/scripts/scope-write.sh`.
```
README.md
README.pt-BR.md
hooks/hooks.json
CHANGELOG.md
docs/plans/**
```
**Arquivos novos declarados:** `README.pt-BR.md`.

## Correções declaradas
| # | arquivo | texto antigo | texto novo |
|---|---|---|---|
| 1 | `README.md` | `The four guards **fail closed**` | as seis cercas |
| 2 | `README.md` | `about 468 tokens always on` | ~772 tokens, medido hoje |
| 3 | `hooks/hooks.json` | `exit 2 is never used` | exit 2 só no `stop-gate`, contrato do evento Stop |
| 4 | `docs/plans/2026-09-14-1750-handoff-0-6-1.md` | `status: accepted` | `status: superado por <handoff novo>` |

## Aceite (EARS)
| # | QUANDO | O SISTEMA DEVE | provado por | falha quando |
|---|--------|----------------|-------------|--------------|
| 1 | um dev abre `README.md` | mostrar a troca de idioma e o TL;DR antes de qualquer tabela | `head -12 README.md \| grep -c 'README.pt-BR.md\|TL;DR'` | imprime menos de 2 |
| 2 | `README.pt-BR.md` é lido ao lado de `README.md` | ter o mesmo número de seções `## ` e de blocos `<details>` | portão de paridade da Verificação | `test` sai 1 |
| 3 | cada README cita um caminho em crase | o caminho existir na árvore | `pointers-check.sh README.md README.pt-BR.md --root .` | `pointers-check: N problem(s)` |
| 4 | o README cita um número | o número bater com o comando: 772 tokens, 30 casos, 64 ataques (50 + 14), 6 cercas | os comandos da varredura acima | qualquer número diferente |
| 5 | `hooks/hooks.json` é lido | a descrição declarar a exceção do `stop-gate` e o manifesto validar | `claude plugin validate . --strict` | qualquer saída diferente de OK |
| 6 | `docs-check.sh docs` roda | um só handoff vivo, o antigo `superado por` o novo | `bash skills/document/scripts/docs-check.sh docs` | `docs-check: N problem(s)` |
| 7 | a frente fecha | as quatro correções declaradas estarem feitas | `plan-preflight.sh <plano> --closing` | `correction NOT DONE` |

## Verificação (após o último commit)
```
bash tests/run.sh
bash tests/attack.sh
bash skills/document/scripts/docs-check.sh docs
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate,rite-gate,stop-gate
bash skills/document/scripts/pointers-check.sh README.md README.pt-BR.md --root .
test "$(grep -c '^## ' README.md)" = "$(grep -c '^## ' README.pt-BR.md)" && test "$(grep -c '<details>' README.md)" = "$(grep -c '<details>' README.pt-BR.md)" && grep -q '(README.pt-BR.md)' README.md && grep -q '(README.md)' README.pt-BR.md || { echo "readme-parity: README.md and README.pt-BR.md disagree in sections, folds or cross-links"; false; }
claude plugin validate . --strict
```
Esperado: `RESULT: gate clean`; `RESULT: every cheat refused, every pass declared`; `docs-check: OK`;
o ledger sem cerca sem refutação; `pointers-check: OK`; o portão de paridade sai 0 em silêncio;
`validate` OK.

## Refutação
- O portão de paridade falha quando uma seção `## ` é removida de `README.pt-BR.md` — injeção com
  `refute.sh --sed` apagando o cabeçalho `## Licença`; texto esperado: `readme-parity: README.md
  and README.pt-BR.md disagree`. Uma vez, ao nascer, registrada em `.roadworthy/refutations.jsonl`.

## Fora do escopo
- Traduzir `docs/`, `CHANGELOG.md`, `SKILL.md` ou `PRINCIPLES.md`: são em inglês por decisão do
  projeto; o pedido foi o README.
- Mudar comportamento de qualquer hook; a única alteração em `hooks/` é uma string descritiva.
- Versão nova do plugin: README não é código; fica em `[Unreleased]`.
- `PRINCIPLES.md`: o dono destacou o princípio 5 nesta sessão; lido inteiro, o texto já descreve
  o `plan-preflight.sh` através do `plan-review-gate` e o `stop-gate`, coerente com 0.6.1. Nada a
  corrigir; se o destaque era um pedido de mudança, é decisão do dono, pois o arquivo é fixado por
  digest e anunciado a cada prompt para quem o usa.

## Política da madrugada
- Decidido à noite, com fonte: nada; esta frente não roda sem o dono.
- Reservado ao dono: push (ordenado neste prompt), qualquer mudança de comportamento em `hooks/`.

## Perguntas abertas
- nenhuma.
