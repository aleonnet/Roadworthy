# O molde do plano pede `~`, não caminho de home; 0.6.2

project: ~/Development/roadworthy
status: proposed

## Contexto

O molde do plano (`skills/plan/templates/plan.md`, linha 3) manda escrever `project:` como caminho
absoluto. Um plano guardado dentro do repositório e commitado carrega então `/Users/<nome>/…`, e a
varredura de privacidade da suíte deste repositório reprova (medido nesta sessão, no primeiro
fechamento da frente do README: `absolute home path found in plugin sources:
docs/plans/done/2026-09-14-1841-readme-em-duas-linguas.md`). O portão de revisão expande `~`
(`hooks/plan-review-gate`, função `same`, `os.path.expanduser`), e o plano desta sessão em modo de
plano declarou `project: ~/Development/roadworthy` e foi eleito e aprovado pelo portão. O molde
ensina uma forma que a própria suíte recusa; o conserto é o molde ensinar a forma que passa.

O molde é lido pelo agente em tempo de execução, da cópia instalada
(`~/.claude/plugins/cache/roadworthy/roadworthy/<versão>/`, um diretório por versão, e
`installed_plugins.json` grava `installPath` e `version`). Para a correção chegar a uma instalação
o plugin precisa de versão nova: 0.6.2, patch, levando junto o `[Unreleased]` de hoje (README em
duas línguas). Nada verificava que os dois manifests e o CHANGELOG concordam na versão; um portão
passa a verificar.

## Faixa de risco

**mínima**: molde, um caso de teste, dois campos de versão e o CHANGELOG. Nenhum hook muda.

## Varredura de impacto (comandos rodados agora)
```
git grep -n -i 'absolute path\|caminho absoluto' -- skills tests README.md README.pt-BR.md docs/reference   # 1 ocorrência no plugin: skills/plan/templates/plan.md:3
git grep -n 'templates/plan.md\|plan\.md' -- skills tests hooks README.md   # consumidores do molde: skills/plan/SKILL.md:31 e tests/scripts/plan-template.sh; nenhum script lê a linha project:
git grep -n '0\.6\.1' -- ':!docs' ':!CHANGELOG.md'                # versão viva só nos dois manifests; o resto é prosa histórica ("until 0.6.1")
grep -n 'expanduser' hooks/plan-review-gate                        # linha 137: o portão expande ~ ao comparar project: com a raiz
git grep -n 'version' -- tests                                     # nenhum teste compara as versões dos manifests com o CHANGELOG
git grep -n "project" hooks skills bin                             # (rodada 1 do leitor) a FORMA project: aparece em hooks/plan-review-gate:224, na negação, absoluta
```

## Mudanças, por arquivo

- `skills/plan/templates/plan.md` — linha 3 passa a `project: ~/<caminho do repositório a partir
  da sua home>`; o parágrafo abaixo ganha a razão: o portão expande `~`, e um caminho absoluto de
  home num arquivo commitado publica o desenho da máquina.
- `tests/scripts/plan-template.sh` — duas asserções novas: a linha `project:` do molde começa com
  `~/`; o molde não contém `/Users/` nem `/home/`. Escritas ANTES do conserto, vermelhas no molde
  atual, verdes depois, refutadas com o defeito plantado.
- `CHANGELOG.md` — `[Unreleased]` vira `[0.6.2] - 2026-09-14` com a entrada do molde; um
  `[Unreleased]` vazio volta acima, como manda o Keep a Changelog.
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — `0.6.1` → `0.6.2`.
- `hooks/plan-review-gate` — a negação "belongs to another project" dizia `Write … a 'project:
  {root}' line`, com a raiz absoluta; passa a escrever a raiz a partir da home (`~/…`) quando o
  repositório está sob ela. Achado do leitor frio na rodada 1: segunda ocorrência da forma, que
  a minha varredura não contou porque procurei o arquivo (`templates/plan.md`) e não a forma
  (`project:`); `git grep -n "project" hooks skills bin` a encontra.
- `tests/hooks/plan-review-gate.sh` — duas asserções: a negação sugere `project: ~/…` (com
  `HOME` na sandbox e o repositório sob ela); um plano que declara `project: ~/…` é eleito e
  passa. A segunda mede o que o CHANGELOG afirmava e nada media.

## Escopo
Alargado na rodada 1 do leitor frio (motivo abaixo, em Mudanças): a negação do portão ensinava a
forma absoluta.
```
skills/plan/templates/plan.md
tests/scripts/plan-template.sh
hooks/plan-review-gate
tests/hooks/plan-review-gate.sh
CHANGELOG.md
.claude-plugin/plugin.json
.claude-plugin/marketplace.json
docs/plans/**
```

## Correções declaradas
| # | arquivo | texto antigo | texto novo |
|---|---|---|---|
| 1 | `skills/plan/templates/plan.md` | `project: <absolute path of the repository this plan belongs to>` | `project: ~/<…>` |
| 2 | `.claude-plugin/plugin.json` | `"version": "0.6.1"` | `"version": "0.6.2"` |
| 3 | `.claude-plugin/marketplace.json` | `"version": "0.6.1"` | `"version": "0.6.2"` |
| 4 | `hooks/plan-review-gate` | `'project: {root}'` | `'project: {hint}'`, com `hint` escrito a partir da home |

## Aceite (EARS)
| # | QUANDO | O SISTEMA DEVE | provado por | falha quando |
|---|--------|----------------|-------------|--------------|
| 1 | o caso do molde roda no molde ANTES do conserto | ficar vermelho nomeando a linha `project:` | `bash tests/scripts/plan-template.sh` | verde |
| 2 | o caso do molde roda no molde consertado | ficar verde | `bash tests/scripts/plan-template.sh` | qualquer `[FAIL]` |
| 3 | um caminho `/Users/…` é plantado na linha `project:` do molde | o caso ficar vermelho com `project line does not start with ~/` e o molde voltar com o mesmo hash | `refute.sh --file skills/plan/templates/plan.md --sed … --expect 'project line does not start with ~/' -- bash tests/scripts/plan-template.sh` | `refute: FAILED` |
| 4 | os manifests e o CHANGELOG são lidos | os três dizerem `0.6.2` | portão de paridade de versão da Verificação | `version-parity: …` |
| 5 | a suíte inteira roda | `RESULT: gate clean`, com o caso do molde dentro | `bash tests/run.sh` | qualquer caso vermelho |
| 6 | a frente fecha | as quatro correções declaradas estarem feitas | `plan-preflight.sh <plano> --closing` | `correction NOT DONE` |
| 7 | o portão nega um plano de outro projeto, com o repositório sob a home | a dica dizer `project: ~/…` | `bash tests/hooks/plan-review-gate.sh` | `the denial hints an absolute home path` |
| 8 | um plano declara `project: ~/…` do repositório do evento | ser eleito e passar | `bash tests/hooks/plan-review-gate.sh` | `a project declared with ~ was not matched` |

## Verificação (após o último commit)
```
bash tests/run.sh
bash tests/attack.sh
bash skills/document/scripts/docs-check.sh docs
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate,rite-gate,stop-gate
bash skills/document/scripts/pointers-check.sh README.md README.pt-BR.md --root .
test "$(grep -c '^## ' README.md)" = "$(grep -c '^## ' README.pt-BR.md)" && test "$(grep -c '<details>' README.md)" = "$(grep -c '<details>' README.pt-BR.md)" && grep -q '(README.pt-BR.md)' README.md && grep -q '(README.md)' README.pt-BR.md || { echo "readme-parity: README.md and README.pt-BR.md disagree in sections, folds or cross-links"; false; }
v="$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])')" && test "$v" = "$(python3 -c 'import json;print(json.load(open(".claude-plugin/marketplace.json"))["plugins"][0]["version"])')" && grep -q "^## \[$v\] - " CHANGELOG.md || { echo "version-parity: plugin.json, marketplace.json and CHANGELOG disagree on the version"; false; }
claude plugin validate . --strict
```
Esperado: os sete de sempre verdes; o portão de paridade de versão sai 0 em silêncio.

## Refutação
- `tests/scripts/plan-template.sh` falha quando a linha `project:` do molde volta a um caminho de
  home — injeção por `sed`: `~/` trocado por `/Users/<alguém>/` na linha `project:` (a string exata
  está no registro da refutação, não aqui: a varredura de privacidade lê este plano); texto
  esperado: `project line does not start with ~/`.
- `tests/hooks/plan-review-gate.sh` falha quando a dica da negação volta à raiz absoluta —
  injeção no portão: `{hint}` trocado por `{root}` na f-string; texto esperado: `the denial hints
  an absolute home path`.
- O portão de paridade de versão falha quando `marketplace.json` fica em `0.6.1` — injeção
  `s/"version": "0.6.2"/"version": "0.6.1"/`; texto esperado: `version-parity:`.

## Fora do escopo
- Mudar como o portão compara `project:`: já expande `~`, medido.
- `skills/plan/SKILL.md`: não diz "absolute"; a regra fica no molde, que é o que se copia.
- O push: ato do dono, com a YubiKey. `claude plugin update` + `/reload-plugins`: depois do push.

## Política da madrugada
- Decidido à noite, com fonte: nada.
- Reservado ao dono: push, `plugin update`, `/reload-plugins`.

## Perguntas abertas
- nenhuma.
