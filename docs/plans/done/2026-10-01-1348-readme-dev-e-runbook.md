# README_DEV e runbook: o que um dev humano precisa para dominar o plugin

status: accepted
project: ~/Development/roadworthy
report: prosa curta, a conclusão primeiro; tabela só quando houver três ou mais itens com prova (fim de fase e fecho); "Seu:" só quando algo depende do dono; nada de "Meu:"

## Contexto

Pedido do dono em 2026-10-01: um `README_DEV.md` conciso para um dev humano dominar o plugin
(arquitetura, como funciona por dentro, como evoluir) e um runbook em `docs/guides/` linkado a
partir dele, aderentes a fontes reais e validadas de boas práticas; depois, commit e push. Não
existe nenhum dos dois hoje, e nada no repositório diz a um dev por onde começar: o `README.md`
é de quem USA o plugin, e o conhecimento de quem o MANTÉM está espalhado em cabeçalhos de 14
scripts, 10 ganchos e num CHANGELOG de 676 linhas. (O plano aprovado dizia 16 scripts; são 14,
medido com `printf '%s\n' skills/*/scripts/*.sh | wc -l`. Corrigido depois da leitura fria.)

Lidos inteiros nesta sessão, antes deste plano: os dez ganchos, `hooks/lib.sh`,
`hooks/run-hook.cmd`, `hooks/hooks.json`, os quatro auxiliares em Python (`shellread.py` nas suas
1.601 linhas), os catorze scripts das skills, as seis skills e seus moldes, `bin/rw-metrics`,
o agente, os princípios, `tests/run.sh`, `tests/lib.sh`, `tests/cases.txt`, os cinco casos de
`tests/meta/`, as fixtures, a bancada, a CI, os dois manifests, os dois READMEs, o CHANGELOG, o
roteiro, o registro da 0.7.0 e o handoff vivo.

**Língua: inglês e português, em par.** O plano nasceu com um arquivo só, em inglês, pela decisão
registrada do projeto para tudo que não é o README de entrada:

docs/plans/done/2026-09-14-1841-readme-em-duas-linguas.md:112 — `são em inglês por decisão do`

**Emenda do dono, 2026-10-01, durante a execução:** *"Precisamos também do README_DEV.pt-BR.md"*.
O guia do dev passa a ter o gêmeo em português, no mesmo arranjo do `README.md` com o
`README.pt-BR.md`: mesmas seções, link cruzado no topo de cada um, e um portão de paridade para
que os dois não se afastem. O runbook segue só em inglês (não foi pedido em português).

**Nome: `README_DEV.md`, como pedido.** Consequência medida: o GitHub só mostra sozinho o arquivo
chamado CONTRIBUTING (fonte abaixo). O `README.md` e o `README.pt-BR.md` ganham uma linha
apontando para ele, que é por onde um dev chega.

## Fontes das práticas (conferidas hoje, cada frase achada por `curl` + `grep` no texto da página)

O que cada fonte manda, em citação literal, e o que isso decide aqui.

1. **matklad, "ARCHITECTURE.md"** (matklad.github.io/2021/02/06/ARCHITECTURE.md.html):
   *"Keep it short: every recurring contributor will have to read it."* ·
   *"only specify things that are unlikely to frequently change."* ·
   *"Start with a bird’s eye overview of the problem being solved. Then, specify a more-or-less
   detailed codemap."* · *"The codemap should answer “where’s the thing that does X?”."* ·
   *"Do name important files, modules, and types. Do not directly link them (links go stale)."* ·
   *"Explicitly call-out architectural invariants. Often, important invariants are expressed as
   an absence of something"* · *"add a separate section on cross-cutting concerns."*
   → é a forma do `README_DEV.md`: visão de cima, mapa do código, invariantes, preocupações
   transversais; nomes em vez de links para código; nenhum número que envelhece.
2. **Diátaxis** (diataxis.fr/start-here, /how-to-guides, /explanation, /reference):
   *"there are fundamentally four identifiable kinds of documentation, that respond to four
   different needs."* · *"Explanation is a discursive treatment of a subject, that permits
   reflection."* · *"A how-to guide always addresses an already-competent user"* ·
   *"If you want x, do y. To achieve w, do z. Use conditional imperatives."* ·
   *"In how-to guides, practical usability is more helpful than completeness."*
   → dois documentos e não um: o `README_DEV.md` EXPLICA (por que é assim), o runbook é guia de
   COMO FAZER (se você quer x, faça y). A referência continua onde já está — `README.md` e os
   cabeçalhos dos arquivos — e não é copiada.
3. **Google, "Documentation Best Practices"** (google.github.io/styleguide/docguide/best_practices.html):
   *"A small set of fresh and accurate docs is better than a large assembly of “documentation”
   in various states of disrepair."* · *"Cut out everything unnecessary, including out-of-date,
   incorrect, or redundant information."* · *"Change your documentation in the same CL as the
   code change."* · *"Dead docs are bad."*
   → teto de tamanho medido no aceite; nada do `README.md` é repetido; e um portão que reprova
   quando um gancho ou script novo não entra no mapa (é o "mesmo CL" virado mecanismo).
4. **Google SRE** (sre.google/sre-book/introduction e sre.google/workbook/on-call):
   *"thinking through and recording the best practices ahead of time in a "playbook" produces
   roughly a 3x improvement in MTTR as compared to the strategy of "winging it.""* ·
   *"They explain the severity and impact of the alert, and include debugging suggestions and
   possible actions to take to mitigate impact and fully resolve the alert."* ·
   *"If your playbooks are a deterministic list of commands that the on-call engineer runs every
   time a particular alert fires, we recommend implementing automation."*
   → a forma de cada entrada do runbook (sintoma, o que significa, como diagnosticar, o que
   fazer, como conferir) e a regra de não escrever passo que já é script: onde há script, a
   entrada é o nome dele. Inferência minha, declarada: a fonte fala de alertas de produção; o
   que aproveito é a forma da entrada, não o número de 3x.
5. **GitHub Docs, "Setting guidelines for repository contributors"**: *"you can add a file with
   contribution guidelines to your project repository's root, docs, or .github folder. When
   someone opens a pull request or creates an issue, they will see a link to that file."*
   → `README_DEV.md` não ganha esse atalho; ver Fora do escopo.
6. **Claude Code, "Create a plugin" e "Hooks reference"** (code.claude.com/docs/en/plugins/create,
   /docs/en/hooks): *"run it with `--plugin-dir`, which loads a plugin for one session without
   installing it"* · *"When you edit the plugin's files during the session, run `/reload-plugins`
   to load the changes."* · *"Add `--strict` to fail on warnings too."* · *"The same happens on
   any exit code other than 2, while exit 2 still blocks"* (o erro não bloqueante).
   → os comandos do runbook para rodar a árvore de trabalho numa sessão real, e a explicação de
   por que uma cerca que morre tem de responder com negação.
7. **Write the Docs, "Docs as Code"**: *"you should be writing documentation with the same tools
   as code"*, com *"Automated Tests"* na lista → os documentos entram nos portões do fecho.

## Faixa de risco

**mínima**: dois documentos novos, uma linha em três documentos existentes, uma entrada no
CHANGELOG. Nenhum gancho, script ou teste muda. O portão novo é uma verificação nova e é refutado
uma vez, ao nascer.

## Varredura de impacto (comandos rodados agora)
```
git ls-files README_DEV.md CONTRIBUTING.md ARCHITECTURE.md docs/guides          # vazio: nenhum existe
git grep -n -i -E 'README_DEV|CONTRIBUTING|ARCHITECTURE.md|docs/guides'           # 3 ocorrências, só a declaração do papel guides; ninguém cita README_DEV
git grep -l 'refutations.jsonl'                                                   # 23 arquivos: a lista do estado local é soletrada em vários lugares do código
grep -n '^export RW_ON_CRASH=' hooks/guard-commit hooks/overnight-guard hooks/plan-review-gate hooks/principles hooks/protect-paths hooks/review-record hooks/rite-gate hooks/scope-lock hooks/session-state hooks/stop-gate   # deny em 6, allow em 2, warn em 2
git grep -n 'README' -- tests .github                                             # nenhum teste nem a CI lê o TEXTO de um README; só nomes em fixtures
bash skills/document/scripts/pointers-check.sh README.md README.pt-BR.md --root . # pointers-check: OK
bash skills/document/scripts/docs-check.sh docs                                   # docs-check: OK
command -v lychee shellcheck claude gh                                            # os quatro instalados nesta máquina
wc -l README.md README.pt-BR.md CHANGELOG.md docs/README.md                       # 409, 422, 676, 15
grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sort | uniq -c               # dez ganchos; rite-gate e plan-review-gate registrados duas vezes
printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | wc -l   # 21 arquivos que o mapa tem de nomear
grep -c . tests/cases.txt                                                         # 34 casos
find tests/sim/scenarios -name '*.json' | wc -l                                   # 15 cenários
gh run list --limit 3                                                             # a CI do último push: success
lychee --offline --root-dir . README.md README.pt-BR.md docs/                     # 22 OK, 0 Errors
b="$(printf '\140')"; m="$(for n in $(grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sed 's/.* //' | sort -u) $(printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | sed 's|.*/||'); do grep -q -E -- "$b([a-z./-]*/)?$n$b" README_DEV.md 2>/dev/null || printf '%s ' "$n"; done)"; test -z "$m" || { echo "dev-map: not named in README_DEV.md: $m"; false; }   # VERMELHO antes do trabalho, nomeando os 31 (a primeira forma do portão, de um arquivo só)
b="$(printf '\140')"; m="$(for f in README_DEV.md README_DEV.pt-BR.md; do for n in $(grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sed 's/.* //' | sort -u) $(printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | sed 's|.*/||'); do grep -q -E -- "$b([a-z./-]*/)?$n$b" "$f" 2>/dev/null || printf '%s:%s ' "$f" "$n"; done; done)"; test -z "$m" || { echo "dev-map: not named: $m"; false; }   # depois da emenda: VERMELHO, nomeando os 31 que faltam no gêmeo em português
test "$(grep -c '^## ' README_DEV.md)" = "$(grep -c '^## ' README_DEV.pt-BR.md)" && grep -q '(README_DEV.pt-BR.md)' README_DEV.md && grep -q '(README_DEV.md)' README_DEV.pt-BR.md || { echo "readme-dev-parity: README_DEV.md and README_DEV.pt-BR.md disagree in sections or cross-links"; false; }   # VERMELHO: o gêmeo ainda não existe
b="$(printf '\140')"; m="$(for f in README_DEV.md README_DEV.pt-BR.md; do for n in $(grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sed 's/.* //' | sort -u) $(printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | sed 's|.*/||'); do grep -q -F -e "$b$n$b" -e "/$n$b" "$f" 2>/dev/null || printf '%s:%s ' "$f" "$n"; done; done)"; test -z "$m" || { echo "dev-map: not named: $m"; false; }   # a forma FINAL do portão, por texto fixo (segunda emenda): verde com os dois guias escritos; vermelha nas três contraprovas da seção Refutação
```

Quatro fatos do código que os documentos vão afirmar, cada um com a linha que o sustenta:

hooks/lib.sh:283 — `printf '%s/.roadworthy' "$root"`
skills/close/scripts/close.sh:506 — `bash -c "$cmd" < /dev/null > "$gate_out" 2>&1 3<&-; rc=$?`
hooks/hooks.json:2 — `The guards fail CLOSED`
tests/meta/hygiene.sh:12 — `RW_FENCES="hooks/lib.sh hooks/principles`

## Mudanças, por arquivo

- `README_DEV.md` — NOVO, em inglês, no máximo 250 linhas, sete seções:
  1. **Start here** — para quem é, o que precisa estar instalado, e os três primeiros comandos
     (um caso sozinho, a suíte, a árvore de trabalho numa sessão real).
  2. **The idea** — a visão de cima: o rito como máquina de estados (sem frente → plano aprovado
     → frente aberta → fechada), quem dispara o quê, e o que fica em disco.
  3. **Code map** — onde mora o que faz X: os dez ganchos (evento, política de pane, o que lê, o
     que grava), os quatro auxiliares em Python e os dois de shell, os catorze scripts por
     skill, e as cinco camadas de teste. Nomes, não links.
  4. **Invariants** — o que tem de continuar verdade, muitas como ausência: nenhuma cerca falha
     aberta; nada de `CLAUDE_PLUGIN_DATA` para evidência de projeto; uma só gramática de glob, um
     só leitor de comandos, uma só gramática de plano; quem julga é o repositório do ALVO; nada
     sob `.roadworthy/` escrito à mão; nenhum caso fora do manifesto.
  5. **Cross-cutting concerns** — a política de pane por gancho, onde mora a evidência, bash 3.2
     e o Python embutido em heredoc, o limite de tempo de um gancho, a lista do estado local
     soletrada em vários arquivos (com o comando que os acha), Windows sem bash.
  6. **Changing things** — o que tocar junto ao mexer num gancho, criar um gancho, uma opção, um
     verbo no leitor de comandos, um caso, um cenário; e a regra da refutação. Cada item aponta a
     entrada do runbook com o passo a passo.
  7. **Where to read next** — `README.md` (referência de uso), o mapa de `docs/`, o roteiro com
     os limites declarados, os registros de decisão, o runbook.
- `README_DEV.pt-BR.md` — NOVO (emenda): o mesmo guia em português do Brasil, seção por seção
  (Comece aqui, A ideia, Mapa do código, Invariantes, Preocupações transversais, Como mudar,
  Onde ler depois), no mesmo teto de 250 linhas. Nomes de arquivos, ganchos, comandos e
  mensagens ficam como estão no código; o que se traduz é a explicação. Cada um dos dois guias
  abre com a linha de troca de idioma apontando para o outro.
- `docs/guides/runbook.md` — NOVO, em inglês, no máximo 300 linhas. Guia de como fazer, uma
  entrada por situação real, cada uma com: quando usar, o que rodar, o que esperar, e o que fazer
  se não for isso. Entradas: rodar a árvore de trabalho numa sessão real; rodar um caso, a suíte,
  os ataques, a bancada; trabalhar neste repositório pelo próprio rito; uma frente que não fecha
  (portão vermelho, "not the front that was approved", abandonar com registro); um turno
  bloqueado no fim; a verificação que só uma pessoa faz; um gancho que nega tudo ou dá erro
  (reproduzir a chamada à mão); ler os livros de registro; provar que uma verificação nova
  consegue falhar; publicar uma versão; a CI vermelha; desligar uma cerca (ato do dono); o
  marcador da madrugada esquecido ligado. Todo comando escrito ali é rodado nesta frente, num
  repositório de brinquedo na pasta temporária da sessão ou neste, e a saída conferida.
- `README.md` e `README.pt-BR.md` — uma linha cada, na seção de testes, apontando para o guia
  do dev na sua língua (`README_DEV.md` no inglês, `README_DEV.pt-BR.md` no português) e para o
  runbook. Nenhum cabeçalho `## ` e nenhum bloco `<details>` novo: o
  portão de paridade continua valendo.
- `docs/README.md` — duas linhas sob a tabela: onde está o guia do dev e onde está o runbook.
- `CHANGELOG.md` — `[Unreleased]` ganha "Added": os dois documentos e o portão do mapa.
- `docs/plans/**` — este plano; o handoff novo, escrito e commitado ANTES do fecho; o handoff das
  11:50 marcado `superado por` o novo e movido para `done/`; este plano movido para `done/`; duas
  linhas no índice de `done/`.

Movimentos, listados antes de executar (dois `git mv`, ambos no fim, antes do fecho):
`docs/plans/2026-10-01-1150-handoff-0-7-0.md` → `docs/plans/done/` e
`docs/plans/2026-10-01-1348-readme-dev-e-runbook.md` → `docs/plans/done/`.

## Escopo
Os globs que `scope-lock` vai impor, lidos deste bloco por `skills/plan/scripts/scope-write.sh`.
```
README_DEV.md
README_DEV.pt-BR.md
docs/guides/runbook.md
README.md
README.pt-BR.md
docs/README.md
CHANGELOG.md
docs/plans/**
```
**Arquivos novos declarados:** `README_DEV.md`, `README_DEV.pt-BR.md`, `docs/guides/runbook.md`.

## Aceite (EARS)
| # | QUANDO | O SISTEMA DEVE | provado por | falha quando |
|---|--------|----------------|-------------|--------------|
| 1 | um dev abre `README_DEV.md` ou o gêmeo em português | trazer as sete seções, na mesma ordem nos dois: Start here, The idea, Code map, Invariants, Cross-cutting concerns, Changing things, Where to read next (no gêmeo, as mesmas sete com o título em português) | `grep '^## ' README_DEV.md README_DEV.pt-BR.md` e o portão `readme-dev-parity` | faltar uma, a ordem for outra, ou `readme-dev-parity:` |
| 2 | os três documentos são medidos | caber no teto: 250 linhas cada guia, 300 o runbook, linhas de até 100 colunas | `wc -l README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md` e `awk 'length > 100' README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md` | passar do teto, ou o `awk` imprimir linha |
| 3 | um gancho registrado, um auxiliar ou um script de skill existe | estar nomeado entre crases nos dois guias | o portão `dev-map` da Verificação | `dev-map: not named: <arquivo>:<nome>` |
| 4 | um dos cinco documentos cita um caminho entre crases | o caminho existir na árvore | `pointers-check.sh README.md README.pt-BR.md README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md --root .` | `pointers-check: N problem(s)` |
| 5 | o runbook manda rodar um comando | o comando ter sido rodado nesta frente e a saída ser a que a entrada descreve | a tabela do handoff: entrada, comando, saída observada | uma entrada sem saída observada |
| 6 | um documento cita um número | não haver número que envelhece (contagem de casos, ataques, cenários, tokens): o documento nomeia o comando que o imprime | `grep -n -E '[0-9]+ (cases\|attacks\|scenarios\|tokens\|casos\|ataques\|cenários)' README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md` | o `grep` imprimir linha |
| 7 | `README.md` e `README.pt-BR.md` são lidos lado a lado | cada um apontar para o guia do dev na sua língua, com a paridade de seções mantida | `grep -c 'README_DEV.md' README.md` e `grep -c 'README_DEV.pt-BR.md' README.pt-BR.md` e o portão de paridade | zero num dos dois, ou `readme-parity:` |
| 8 | `docs-check.sh docs` e o `lychee` rodam | um só handoff vivo, este plano no índice de `done/`, nenhum link local quebrado | `bash skills/document/scripts/docs-check.sh docs` e `lychee --offline --root-dir . README.md README.pt-BR.md README_DEV.md README_DEV.pt-BR.md docs/` | `docs-check: N problem(s)`, ou erros no `lychee` |
| 9 | a frente fecha | os dez portões rodarem frescos sobre o último commit, e o push levar a CI ao verde | `bash skills/close/scripts/close.sh` e `gh run list --limit 3` | `close: gaps_found`, ou um job vermelho |

## Verificação (após o último commit)
```
bash tests/run.sh
bash tests/attack.sh
bash skills/document/scripts/docs-check.sh docs
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate,rite-gate,stop-gate,session-state
bash skills/document/scripts/pointers-check.sh README.md README.pt-BR.md README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md --root .
test "$(grep -c '^## ' README.md)" = "$(grep -c '^## ' README.pt-BR.md)" && test "$(grep -c '<details>' README.md)" = "$(grep -c '<details>' README.pt-BR.md)" && grep -q '(README.pt-BR.md)' README.md && grep -q '(README.md)' README.pt-BR.md || { echo "readme-parity: README.md and README.pt-BR.md disagree in sections, folds or cross-links"; false; }
v="$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])')" && test "$v" = "$(python3 -c 'import json;print(json.load(open(".claude-plugin/marketplace.json"))["plugins"][0]["version"])')" && grep -q "^## \[$v\] - " CHANGELOG.md || { echo "version-parity: plugin.json, marketplace.json and CHANGELOG disagree on the version"; false; }
claude plugin validate . --strict
b="$(printf '\140')"; m="$(for f in README_DEV.md README_DEV.pt-BR.md; do for n in $(grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sed 's/.* //' | sort -u) $(printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | sed 's|.*/||'); do grep -q -F -e "$b$n$b" -e "/$n$b" "$f" 2>/dev/null || printf '%s:%s ' "$f" "$n"; done; done)"; test -z "$m" || { echo "dev-map: not named: $m"; false; }
test "$(grep -c '^## ' README_DEV.md)" = "$(grep -c '^## ' README_DEV.pt-BR.md)" && grep -q '(README_DEV.pt-BR.md)' README_DEV.md && grep -q '(README_DEV.md)' README_DEV.pt-BR.md || { echo "readme-dev-parity: README_DEV.md and README_DEV.pt-BR.md disagree in sections or cross-links"; false; }
```
Esperado: `RESULT: gate clean`; `RESULT: every cheat refused, every pass declared`; `docs-check: OK`;
`9 fence(s), 0 legacy, 0 without a record`; `pointers-check: OK`; os portões de paridade e de mapa
saem 0 em silêncio; `Validation passed`. Os oito primeiros são os que o repositório já tem; muda
o quinto (três arquivos a mais) e nascem o nono (o mapa, nos dois guias) e o décimo (a paridade
dos dois guias).

## Refutação
- **Segunda emenda, 2026-10-01: a contraprova reprovou o próprio portão, e ele foi consertado.**
  A injeção declarada acima neste plano (trocar `shellread.py` por `shellread-py` no guia) deixou
  o `dev-map` VERDE: o nome entrava numa expressão regular, e o ponto de `shellread.py` casava
  com qualquer caractere. `refute.sh` disse `the check stayed green with the defect injected`.
  O portão passa a comparar por TEXTO FIXO (`grep -F`: o nome entre crases, ou precedido de `/`
  e seguido de crase). É a única mudança desta emenda; escopo e demais portões ficam como estão.
- O `dev-map` na forma final, refutado três vezes, cada uma com o arquivo restaurado e conferido
  por SHA-256 e gravada em `.roadworthy/refutations.jsonl` pelo próprio script: a mesma troca
  de `shellread.py` → `dev-map: not named: README_DEV.md:shellread.py`; `rite-gate` tirado das
  crases no gêmeo → `dev-map: not named: README_DEV.pt-BR.md:rite-gate`; `close.sh` nomeado só
  dentro de nomes maiores → `dev-map: not named: README_DEV.md:close.sh`.
- O `readme-dev-parity`, refutado duas vezes: um cabeçalho `## ` apagado do gêmeo, e o link
  cruzado do guia em inglês trocado; nas duas, `readme-dev-parity: README_DEV.md and
  README_DEV.pt-BR.md disagree`.
- Classe do que faltou no meu levantamento: escrevi um portão com um nome de arquivo dentro de
  uma expressão regular sem escapar o ponto, e só a contraprova mostrou.

## Fora do escopo
- Um `CONTRIBUTING.md` de três linhas apontando para o `README_DEV.md`, que daria o atalho do
  GitHub. Não foi pedido; fica registrado como opção do dono.
- Versão em português do runbook: a emenda pediu o guia; o runbook fica em inglês.
- Mudar o comportamento de qualquer gancho, script ou teste. Se a escrita achar um defeito no
  código, ele vai para o handoff como achado, não para esta frente.
- Versão nova do plugin: documento não é código; fica em `[Unreleased]`.
- Repetir o que o `README.md` já diz (opções, o que cada gancho garante, limites declarados): o
  guia aponta, não copia.

## Política da madrugada
- Decidido à noite, com fonte: nada; esta frente não roda sem o dono.
- Reservado ao dono: o push (ordenado neste pedido, feito depois do fecho verde).

## Perguntas abertas
- nenhuma.
