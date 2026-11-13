# Roadworthy 0.8.0: o plugin garante o rito em sete passos, sem trava que dependa de comando manual do dono

status: accepted
project: ~/Development/roadworthy
base: 2f1b0ed
report: prosa curta, conclusão primeiro; uma única tabela (item, prova, estado) só no fecho da frente

Este plano supera o rascunho `2026-11-13-1120-roadworthy-garantir-o-rito-em-sete-passos.md`
(mesma pasta), que fica em disco e é marcado como superado no primeiro ato da execução. As três
perguntas abertas do rascunho foram respondidas pelo dono em 2026-11-13 com "sim": vale a palavra
`aprovado` sozinha e também a linha `rw-human: aprovado`; a aprovação do fecho nasce ligada para
todo usuário do plugin; e os arquivos do dono passam a ser editados por frase dele no chat.

## Context

O dono definiu em 2026-11-13 "O rito da casa em sete passos" (topo de `~/.claude/CLAUDE.md`) e
mandou revisar tudo contra ele, inclusive o plugin, que nas palavras dele "tem deadlocks, não deixa
editar/criar planos multi repo", deveria "criar disciplina, eficiência em prol da qualidade e não
travas desnecessárias que dependam de meus comandos manuais", e onde "a frente somente é fechada
com minha aprovação".

Lido inteiro nesta sessão, aberta no repositório do plugin (versão 0.7.1, HEAD `2f1b0ed`): todos
os ganchos de `hooks/` menos `run-hook.cmd`; `scope-write.sh`, `plan-preflight.sh`, `close.sh`; o
modelo de plano e as skills de plano e de fecho; `tests/run.sh`, `tests/lib.sh` e os casos de
`plan-review-gate`, `principles`, `rite-gate`, `close`, `scope-write` e `plan-preflight`; os quatro
README, o `CHANGELOG.md` e os dois manifestos; e o registro de 2026-10-16 em `docs/roadmap/`.
Lido em parte, por busca, e a ler inteiro antes de ser tocado: `tests/sim/rite-sim.py`,
`tests/attack.sh`, `tests/meta/*.sh`, `docs/guides/runbook.md`, `docs/reference/roadmap.md`.

O que o código faz hoje contra cada passo do rito, medido aqui:

| Passo do rito | O que o plugin garante hoje | Lacuna medida |
|---|---|---|
| Plano | pré-voo; banca só quando o arquivo de exigências do projeto pede | plano submetido com a sessão dentro de um subprojeto é recusado como "N planos vivos" (13 recusas) |
| Executar | frente só abre de plano aprovado; escopo travado | plano que cita vários repositórios abre frente num só; a aprovação "não é achada" nos outros (27 recusas) |
| Fechar | portões frescos depois do último commit | o fecho grava `passed` e solta o escopo sem a aprovação do dono (`skills/close/scripts/close.sh:569`); árvore suja por arquivo do dono manda fazer `git stash` |
| Atos do dono | resposta a verificação humana pelo chat | aceitar o arquivo de princípios e mudar os cinco arquivos dele só fora do agente |

Negações gravadas desde 2026-10-02 nos livros do monorepo NavBlue, contadas nesta sessão por
script Python inline: 113 no total — 31 por caminho fora do escopo, 27 por aprovação não achada
ou frente "não aprovada", 18 por falta de frente, 13 por "N planos vivos", 9 por pré-voo vermelho,
6 por arquivo de configuração do dono, 3 por plano de outro projeto, 6 de outros tipos.

Resultado pretendido: nenhuma das sete lacunas abaixo exige que o dono rode comando no terminal,
e a frente só fecha com o "aprovado" dele.

## Risk band

**Crítica.** A área tocada são as próprias cercas (`hooks/`) e os dois scripts que abrem e fecham
frente. Cada garantia nova entra com o teste que reprova antes do conserto, a contraprova com o
defeito plantado (`skills/refute/scripts/refute.sh`, arquivo restaurado por impressão digital), a
suíte inteira verde e leitor frio sobre o diff antes do fecho.

## Impact sweep (commands run now)

```
git grep -n -E 'approved_in_transcript|approved_in_ledger|planblocks.py" approved|judge_open' -- hooks skills tests bin
git grep -n 'preexisting' -- hooks skills tests bin
git grep -n 'rm -f .roadworthy/scope\|end_closing passed' -- hooks skills
git grep -c -E "close: passed|scope released|rm -f .*\.roadworthy/scope" -- tests evals evals-round2 bin docs/guides skills
git grep -n 'git stash' -- hooks skills docs/guides README.md README.pt-BR.md tests
env | grep -c '^CLAUDE_PLUGIN_OPTION_'
git grep -c 'scope-write.sh' -- tests/hooks tests/scripts tests/meta tests/fixtures tests/attack.sh tests/bench
grep -n 'close"\|\$close' skills/overnight/scripts/overnight-close.sh
bash tests/run.sh
```

O que cada um mostrou:

- **Quem consulta a aprovação de um plano:** só `hooks/rite-gate` (função `judge_open`, que chama
  `planblocks.py approved`) e `hooks/frontcheck.py` (função `approved`, a cada escrita). Os testes
  que a exercitam estão em `tests/hooks/plan-review-gate.sh` e `tests/hooks/rite-gate.sh`.
- **Quem lê o que já estava mexido na abertura (`preexisting`):** `scope-write.sh` grava,
  `hooks/frontcheck.py` lê para o aviso de mudança fora do escopo. O fecho não lê: recusa a árvore
  suja e, além disso, conta todo arquivo não rastreado como "tocado pela frente".
- **Onde o escopo é solto:** dois lugares em `close.sh`, o abandono e o fecho verde.
- **Quem depende de o fecho verde soltar o escopo na hora:** 7 asserções em
  `tests/scripts/close.sh`, 4 em `tests/hooks/rite-gate.sh`, 2 em `tests/hooks/principles.sh`, 2 em
  `tests/hooks/guard-commit.sh`, 1 em cada de `scope-write`, `session-state` e `goldens`, e o
  runbook. Os que abrem a frente pelo script do rito (e não com escopo escrito à mão) passam a
  esperar a aprovação e são tocados pela mudança 2: os arquivos de teste que chamam
  `scope-write.sh` são `tests/scripts/scope-write.sh`, `tests/scripts/close.sh`,
  `tests/hooks/rite-gate.sh`, `tests/hooks/principles.sh`, `tests/fixtures/repo.sh`,
  `tests/fixtures/plan.sh`, `tests/attack.sh` e `tests/bench/bench.sh`. (`tests/scripts/shellread.sh`
  também traz o nome, mas só na tabela do leitor de comandos: não abre frente.)
- **O simulador de sessões:** 12 dos 15 cenários rodam o fecho, e 5 deles aprovam um plano e
  fecham na mesma sessão (`live-02`, `live-03`, `live-04`, `live-05`, `live-10`). O simulador já
  sabe gravar o arquivo de exigências do projeto na preparação de um cenário.
- **O fecho da madrugada** (`overnight-close.sh --run`) chama o fecho e recusa a noite quando ele
  sai com erro; depende, portanto, do código de saída de um fecho que fica esperando o dono.
- **O leitor de comandos não vê o agente rodando o próprio gancho de prompt:** para
  `bash hooks/principles < evento.json` e para o mesmo por `run-hook.cmd` ele não devolve alvo
  nenhum, e a cerca deixa passar. Hoje isso já permite ao agente forjar a resposta de uma
  verificação humana. E `ROADWORTHY_DATA=/tmp/x bash .../scope-write.sh plano.md` é lido como
  abertura comum de frente.
- **Conselho de `git stash`:** no texto do fecho, numa asserção de `tests/scripts/close.sh` e no
  runbook. Os outros resultados são o leitor de comandos tratando `git stash -u` como remoção, que
  não muda.
- **As opções do plugin não chegam ao shell onde o agente roda os scripts:** 0 variáveis. Logo o
  fecho não consegue ler uma opção, e um livro apontado por variável de ambiente é um livro que o
  agente escolhe. A exigência do "aprovado" do dono tem de valer por construção e só poder ser
  dispensada num arquivo do dono.
- **Suíte inteira hoje:** 34 casos. A primeira rodada desta sessão deu 1 vermelho, por um arquivo
  de bytecode que o meu próprio script de medição deixou em `hooks/` (defeito meu, removido pelo
  dono); a segunda rodada, com a árvore limpa, terminou em `RESULT: gate clean`, sem falha.

Medido por script Python inline sobre as transcrições dos últimos 45 dias (monorepo NavBlue e
este repositório), 43 saídas de modo de plano aprovadas:

- em 20 delas a chamada aparece gravada duas vezes com a mesma identificação, a segunda com o
  plano vazio (registro do tipo `api-request-blob`); a função que procura a aprovação guarda a
  última, a vazia (`hooks/planblocks.py:120`), e por isso responde "não aprovado". A confirmação
  do registro de 2026-10-16 foi reproduzida aqui: `False`;
- em 8 a resposta grande foi para arquivo, e nas 8 a frase procurada continua no corpo gravado.
  Isso corrige o registro de 2026-10-16: ler o arquivo da resposta não é necessário;
- as 13 recusas "N planos vivos" têm uma causa só: o arquivo que a chamada nomeia é descartado
  pelo filtro "planos que declaram este projeto" antes de ser eleito
  (`hooks/plan-review-gate:290`). Nove aconteceram com a sessão parada dentro de um subprojeto.

## Changes, per file

### 1. Um plano que cita vários repositórios abre uma frente em cada um, num só ato

- `hooks/planblocks.py` — função nova que separa as linhas do escopo e dos portões por
  repositório. Linha de escopo relativa é resolvida contra o repositório do plano; linha absoluta
  ou com `~`, como está. O repositório de cada linha é o do trecho literal do caminho (até o
  primeiro curinga), achado pela mesma regra de `rw_target_root` em `hooks/lib.sh`: repositório
  aninhado sem pasta `.roadworthy` responde ao mais próximo acima dele que tenha uma; não havendo,
  é ele mesmo. Caminho em repositório nenhum fica com o
  repositório do plano, por extenso, como a trava de escopo já compara hoje. Portão cujo comando
  começa por `cd <pasta>` vai para o repositório dessa pasta; os demais ficam com o do plano.
- `skills/plan/scripts/scope-write.sh` — abre, num ato, a frente em cada repositório citado:
  grava em cada um o escopo já relativo a ele, os portões dele e a fotografia. A fotografia passa
  a guardar as listas inteiras do plano (para conferir a impressão digital da aprovação), as listas
  locais (para a trava), a raiz do plano (de onde os portões rodam, para o `cd` escrito no plano
  valer) e a lista dos repositórios da frente. Recusa repositório citado que fique sem portão, e
  recusa tudo, sem gravar nada, se algum deles já tiver frente viva de outro plano.
- `hooks/frontcheck.py` — confere a impressão digital pelas listas inteiras quando a fotografia as
  traz, e procura a aprovação também no livro do repositório do plano.
- `hooks/rite-gate` (`judge_open`, linha `hooks/rite-gate:185`) — a aprovação é do plano: procura
  no livro de onde a frente abre, no livro do repositório do plano e na transcrição.
- `skills/close/scripts/close.sh` — os portões rodam a partir da raiz do plano. Rodado na raiz do
  plano, o fecho percorre todos os repositórios da frente (árvore, escopo, portões de cada um) e só
  com todos verdes segue adiante; rodado num dos outros, mede o que é dele e diz de onde a frente
  fecha.
- `skills/plan/scripts/plan-preflight.sh` — caminho de escopo com `~` é expandido antes de ser
  procurado; hoje seria dado como inexistente.
- Caso novo `tests/scripts/front-roots.sh` (e a linha dele em `tests/cases.txt`): uma tabela de
  caminhos para a qual o resolvedor em Python e `rw_target_root` têm de dar a mesma resposta.

Direção do dono mantida: o plano continua pertencendo ao repositório da sessão; o que muda é que o
escopo dele pode citar outros. O rascunho propunha também aceitar plano de outro projeto quando o
escopo citasse o da sessão; fica de fora, porque contradiz essa direção e a mudança 7 já resolve o
caso medido.

### 2. A frente só fecha com o "aprovado" do dono, dado no chat

- **A exigência vale para toda frente que o script do rito abriu** (a que tem fotografia), sem
  opção e sem consulta a livro. Só é dispensada por uma linha `owner_approval: off` no arquivo de
  exigências do projeto (`.roadworthy/rites`) da raiz do plano — arquivo do dono, negado ao agente,
  que o dono escreve pelo chat (mudança 4). Palavra desconhecida ali recusa o fecho, como já
  acontece com `diff_review`. Escopo escrito à mão, sem fotografia, fecha como hoje. Nada disso
  depende de variável de ambiente nem de qual livro o comando enxerga.
- `skills/close/scripts/close.sh` — com os portões verdes numa frente que pede a aprovação: abre
  o item "aprovação do dono para fechar <plano>", com a árvore medida e a impressão digital do
  plano; o estado fica `needs_human`; o escopo fica; a mensagem manda o agente relatar e parar; o
  script sai com 0, porque os portões passaram (o fecho da madrugada segue e deixa a frente
  esperando a manhã; o handoff dela passa a dizer isso). Quando o dono aprova esse item: se todos
  os portões continuam frescos para a árvore atual, em todos os repositórios da frente, grava
  `passed` e solta o escopo em cada um; se a árvore mudou, a aprovação fica registrada, a frente
  continua aberta e a resposta manda rodar o fecho de novo, que pedirá a aprovação da árvore nova.
  (O rascunho dizia "sem pedir de novo"; aprovar uma árvore que os portões não mediram não é o que
  "a frente só fecha com a minha aprovação" quer dizer.) Reprovação: `gaps_found`, escopo mantido,
  motivo no livro. Abandonar a frente encerra o item dela, para um pedido velho não ficar aberto.
- `hooks/principles` — além de `rw-human: ...`, aceita a mensagem inteira `aprovado`, `aprovada`
  ou `approved` (e `reprovado <motivo>`) quando há exatamente um item de aprovação de fecho aberto
  e ele é o da frente viva. O item é procurado na raiz do plano, achada pela fotografia do
  repositório a que a pasta da sessão responde — pela regra de `rw_target_root`, e não pela de
  `rw_root` que o gancho usa hoje, para um subprojeto sem pasta `.roadworthy` chegar ao de cima:
  funciona com a sessão parada em qualquer repositório da frente. O que foi feito volta no contexto do agente, como hoje.
- `hooks/shellread.py` e `hooks/rite-gate` — o agente rodar o próprio gancho de prompt
  (`hooks/principles`, `run-hook.cmd principles`, `hooks/ownerline.py`) passa a ser lido como ato
  de pessoa e negado, como já é `close.sh --human`. Primeiro a linha na tabela de
  `tests/scripts/shellread.sh`, depois o leitor; e o ataque entra em `tests/attack.sh` como
  recusado. O que continua sendo o limite estrutural já declarado no README: um programa em disco
  que o agente escreva e rode alcança o que os ganchos alcançam.
- `hooks/hooks.json` — tempo-limite do gancho de prompt de 10 para 30 segundos: aprovar passa a
  conferir os portões de cada repositório da frente, e gancho que estoura o tempo não registra.
- `skills/overnight/scripts/overnight-close.sh` e o modelo de handoff da madrugada — dizem que a
  frente espera a aprovação do dono.
- `skills/close/SKILL.md`, `skills/plan/SKILL.md` — o fecho termina em "aguardando a aprovação do
  dono"; o agente pede e para.
- Testes e cenários que fecham frente aberta pelo script do rito: os que não tratam da aprovação
  declaram `owner_approval: off` no arquivo de exigências da preparação (nos cenários `live-02`,
  `live-03`, `live-05`, `live-10` e nos demais que fecham); `live-04`, que já trata de verificação
  humana, ganha o passo da aprovação do dono. Cada um é lido inteiro antes de ser tocado. O
  arquivo de exigências posto num repositório de brinquedo é commitado antes do fecho: o fecho
  conta um arquivo desses não commitado como árvore suja.

### 3. A aprovação de um plano é achada sem `--owner`

- `hooks/planblocks.py` (`approved_in_transcript`) — guarda o primeiro plano não vazio de cada
  chamada; um registro repetido e vazio não apaga o cheio. Mais nada: as respostas gravadas em
  arquivo já trazem a frase no corpo (medido acima).
- O resto da causa é a mudança 1 (`judge_open` consultando o livro do repositório do plano).
- Teste com um trecho de transcrição real, anonimizado, em `tests/fixtures/`.

### 4. Os atos do dono passam pelo chat

- Arquivo novo `hooks/ownerline.py` — lê do prompt do dono as linhas de ordem (`rw-human:`,
  `rw-principios:`, `rw-config:` e a palavra sozinha da mudança 2) numa gramática só, com tabela de
  casos. Só vale no começo de linha; no meio de frase não é ordem.
- `hooks/principles` —
  `rw-principios: aceito` grava a impressão digital nova do arquivo de princípios e cala o aviso;
  `rw-config: [<repositório>] <arquivo> + <linha>` acrescenta e `- <linha>` retira uma linha de
  `protected`, `free`, `rites`, `overnight-rules` ou `standing-gates`; para `docs.json` a forma é
  `<chave> = <valor>`. Sem repositório, vale o da sessão. Arquivo desconhecido, linha a retirar
  que não existe ou JSON que ficaria inválido: nada é gravado e a recusa é dita.
- `hooks/rite-gate` continua negando esses arquivos ao agente pelas duas portas.
- Limite declarado, igual ao que `rw-human:` já tem: o canal confia no prompt que a pessoa
  submeteu; um texto colado por ela que traga uma dessas linhas no começo de linha é ordem dela.
  Entra em `docs/reference/roadmap.md` e como ataque declarado em `tests/attack.sh`.

### 5. O que já estava mexido quando a frente abriu não trava o fecho

- `skills/close/scripts/close.sh` — caminho fora do escopo que a fotografia registrou na abertura,
  com o mesmo conteúdo, deixa de contar como árvore suja e como "arquivo tocado fora do escopo".
  Se mudou desde a abertura, o fecho recusa nomeando o caminho e dizendo as saídas que existem (o
  dono commitar, ou liberar a pasta com `rw-config: free + <glob>`). O conselho de `git stash` sai
  do texto, do teste e do runbook.

### 6. Portões permanentes do projeto

- Arquivo novo do dono, rastreado: `.roadworthy/standing-gates`, um comando por linha.
- `skills/plan/scripts/scope-write.sh` — acrescenta esses comandos aos portões de toda frente, e
  os guarda à parte na fotografia, para a impressão digital do plano não mudar.
- `hooks/rite-gate` — o arquivo entra na lista dos arquivos do dono (passam de cinco para seis),
  negado ao agente; o dono o escreve pela mudança 4.

### 7. O plano que a chamada nomeia é o plano

- `hooks/plan-review-gate` — quando a chamada traz o arquivo do plano e ele é um candidato vivo, é
  ele o eleito, antes do filtro por projeto; depois é julgado como qualquer um. E deixa de ser "de
  outro projeto" o plano cujo repositório declarado contém o repositório onde a sessão está parada
  (a sessão entrou num subprojeto); plano de projeto sem relação continua recusado pelo nome.

### Documentação e versão

- `README.md` e `README.pt-BR.md` — a primeira frente (o passo de fechar), a linha e a letra miúda
  de `principles`, `rite-gate` e `plan-review-gate`, o que cada skill roda, e a tabela dos arquivos
  do projeto (`standing-gates`, e `owner_approval: off` entre as exigências).
- `README_DEV.md` e `README_DEV.pt-BR.md` — o desenho do rito (o fecho espera o dono), o mapa do
  código (`hooks/ownerline.py`), os invariantes 6 a 8.
- `docs/guides/runbook.md`, `docs/reference/roadmap.md`, `docs/README.md` (as três linhas de
  2026-10-16 já pendentes na árvore entram no primeiro commit).
- O registro de 2026-10-16 em `docs/roadmap/` recebe `status: aceito` e um parágrafo com o
  desfecho e a correção medida.
- `CHANGELOG.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — 0.8.0.
- Cabeçalho de cada gancho mudado: a linha datada `Refuted`, que um portão lê.

### Ordem da execução

1. Marcar o rascunho e este arquivo de modo de plano como superados pela cópia de nome datado em
   `docs/plans/`, criar o ramo da frente e abrir a frente dessa cópia (`scope-write.sh`).
2. Ler inteiros os arquivos listados no Context como lidos em parte.
3. Uma mudança por commit, na ordem 3, 7, 5, 6, 1, 2, 4: teste que reprova, conserto, contraprova.
4. Documentação e versão; suíte inteira; leitor frio sobre o diff.
5. Handoff novo em `docs/plans/` (o das 20:13 de 2026-10-01 marcado como superado), linha da
   frente na memória, fecho. A frente espera o "aprovado" do dono; merge e push pelo prompt de
   permissão; no fim, o comando de atualização do plugin instalado fica com o dono
   (`claude plugin update roadworthy@roadworthy`), porque os ganchos que rodam são a cópia
   instalada.

## Scope

```
hooks/**
skills/**
tests/**
docs/**
README.md
README.pt-BR.md
README_DEV.md
README_DEV.pt-BR.md
CHANGELOG.md
.claude-plugin/plugin.json
.claude-plugin/marketplace.json
```

## Acceptance (EARS)

| # | WHEN | THE SYSTEM SHALL | proved by | fails when |
|---|------|------------------|-----------|------------|
| 1 | um plano cita caminhos de dois repositórios | abrir uma frente em cada um, com o escopo e os portões de cada um | `bash tests/scripts/scope-write.sh` | `a plan citing two repositories opened only one front` |
| 2 | o agente abre essa frente com a aprovação gravada só no repositório do plano | deixar abrir, e negar quando não há aprovação em lugar nenhum | `bash tests/hooks/rite-gate.sh` | `an approved plan could not open its front in a second repository` |
| 3 | o agente escreve dentro do escopo no segundo repositório | honrar a frente | `bash tests/hooks/rite-gate.sh` | `a front opened in a second repository was not honoured` |
| 4 | o mesmo caminho é dado ao resolvedor em Python e a `rw_target_root` | responder o mesmo repositório | `bash tests/scripts/front-roots.sh` | `the two resolvers of a file's repository disagree` |
| 5 | os portões passam numa frente que pede a aprovação do dono | manter o escopo e ficar em `needs_human` | `bash tests/scripts/close.sh` | `the front closed without the owner's approval` |
| 6 | o dono escreve `aprovado` com uma aprovação de fecho aberta e os portões frescos, com a sessão parada no segundo repositório da frente | gravar `passed` e soltar o escopo em todos os repositórios da frente | `bash tests/hooks/principles.sh` | `the owner's approval in the prompt did not close the front` |
| 7 | o dono aprova e a árvore mudou desde os portões | registrar, manter a frente aberta e mandar fechar de novo | `bash tests/hooks/principles.sh` | `an approval closed a tree the gates never measured` |
| 8 | o dono escreve `reprovado <motivo>` | manter o escopo, gravar `gaps_found` e o motivo | `bash tests/hooks/principles.sh` | `a rejection released the scope or lost its reason` |
| 9 | o agente digita a resposta do dono, ou roda ele mesmo o gancho de prompt com um evento que traz `aprovado` ou `rw-config:` | negar | `bash tests/hooks/rite-gate.sh` | `the agent approved its own closing` |
| 10 | o escopo foi escrito à mão, ou o arquivo de exigências do dono diz `owner_approval: off` | fechar como hoje; e recusar o fecho quando a palavra ali é desconhecida | `bash tests/scripts/close.sh` | `a front that asked for no approval was left waiting` |
| 11 | a transcrição traz a chamada aprovada duas vezes, a segunda vazia | achar a aprovação; e não achar quando a resposta é de recusa | `bash tests/hooks/plan-review-gate.sh` | `an approval recorded twice in the transcript was not found` |
| 12 | o dono escreve `rw-principios: aceito` | gravar a impressão digital nova e calar o aviso | `bash tests/hooks/principles.sh` | `the owner's acceptance did not update the pin` |
| 13 | o dono escreve `rw-config: protected + lib/auth/**` e depois a mesma linha com `-` | acrescentar e retirar a linha | `bash tests/hooks/principles.sh` | `the owner's line in the prompt did not change the file` |
| 14 | a linha `rw-config:` vem no meio de frase ou nomeia arquivo desconhecido | não gravar nada e dizer a recusa | `bash tests/hooks/principles.sh` | `a line that is not the owner's order changed a file` |
| 15 | um arquivo fora do escopo já estava mexido na abertura e segue igual | fechar sem pedir `git stash`; e recusar, nomeando-o, se mudou depois | `bash tests/scripts/close.sh` | `a file that was already changed when the front opened blocked the closing` |
| 16 | o projeto declara portões permanentes | rodá-los em todo fecho, sem mudar a impressão digital do plano | `bash tests/scripts/scope-write.sh` | `a standing gate did not run at the closing` |
| 17 | o agente tenta editar o arquivo dos portões permanentes | negar | `bash tests/hooks/rite-gate.sh` | `the agent edited the standing gates` |
| 18 | a chamada nomeia o arquivo do plano e outros planos declaram o projeto | eleger o nomeado | `bash tests/hooks/plan-review-gate.sh` | `the plan the call named was not elected` |
| 19 | a sessão está num repositório aninhado no do plano | aceitar o plano; e recusar o de projeto sem relação | `bash tests/hooks/plan-review-gate.sh` | `a plan of the project that holds this repository was refused` |
| 20 | o escopo traz um caminho escrito com `~` | achá-lo | `bash tests/scripts/plan-preflight.sh` | `a scope path written from home was called missing` |
| 21 | o agente abre a frente com `ROADWORTHY_DATA` apontando outro livro, e os portões passam | manter a exigência da aprovação do dono | `bash tests/scripts/close.sh` | `moving the ledger dropped the owner's approval` |
| 22 | uma sessão simulada aprova o plano, trabalha, fecha e o dono aprova | chegar a `passed` sem passo negado | `bash tests/meta/rite-liveness.sh` | `the rite has a dead end` |

## Verification (after the last commit)

Os dez portões que o repositório já declara, copiados de `.roadworthy/gates`.

```
bash tests/run.sh
bash tests/attack.sh
bash skills/document/scripts/docs-check.sh docs
bash skills/refute/scripts/refute-ledger.sh hooks --sources principles,protect-paths,scope-lock,guard-commit,overnight-guard,plan-review-gate,rite-gate,stop-gate,session-state
bash skills/document/scripts/pointers-check.sh README.md README.pt-BR.md README_DEV.md README_DEV.pt-BR.md CONTRIBUTING.md docs/guides/runbook.md --root .
test "$(grep -c '^## ' README.md)" = "$(grep -c '^## ' README.pt-BR.md)" && test "$(grep -c '<details>' README.md)" = "$(grep -c '<details>' README.pt-BR.md)" && grep -q '(README.pt-BR.md)' README.md && grep -q '(README.md)' README.pt-BR.md || { echo "readme-parity: README.md and README.pt-BR.md disagree in sections, folds or cross-links"; false; }
v="$(python3 -c 'import json;print(json.load(open(".claude-plugin/plugin.json"))["version"])')" && test "$v" = "$(python3 -c 'import json;print(json.load(open(".claude-plugin/marketplace.json"))["plugins"][0]["version"])')" && grep -q "^## \[$v\] - " CHANGELOG.md || { echo "version-parity: plugin.json, marketplace.json and CHANGELOG disagree on the version"; false; }
claude plugin validate . --strict
b="$(printf '\140')"; m="$(for f in README_DEV.md README_DEV.pt-BR.md; do for n in $(grep -o 'run-hook.cmd\\" [a-z-]*' hooks/hooks.json | sed 's/.* //' | sort -u) $(printf '%s\n' hooks/*.py hooks/lib.sh hooks/run-hook.cmd skills/*/scripts/*.sh bin/rw-metrics | sed 's|.*/||'); do grep -q -F -e "$b$n$b" -e "/$n$b" "$f" 2>/dev/null || printf '%s:%s ' "$f" "$n"; done; done)"; test -z "$m" || { echo "dev-map: not named: $m"; false; }
test "$(grep -c '^## ' README_DEV.md)" = "$(grep -c '^## ' README_DEV.pt-BR.md)" && grep -q '(README_DEV.pt-BR.md)' README_DEV.md && grep -q '(README_DEV.md)' README_DEV.pt-BR.md || { echo "readme-dev-parity: README_DEV.md and README_DEV.pt-BR.md disagree in sections or cross-links"; false; }
```

Expected: cada um sai com 0; `tests/run.sh` termina em `RESULT: gate clean`, com 35 casos (os 34
de hoje mais `front-roots`).

## Refutation

Cada uma plantada sozinha com `skills/refute/scripts/refute.sh`, contra o caso citado no Aceite, e
o arquivo restaurado com a impressão digital conferida. O texto esperado é o da coluna "fails when".

- `scope-write.sh` abrindo a frente só no repositório do plano → aceite 1.
- `judge_open` voltando a consultar só o livro de onde a frente abre → aceite 2.
- `frontcheck.py` voltando a procurar a aprovação só no livro local → aceite 3.
- A regra do repositório aninhado retirada do resolvedor em Python → aceite 4.
- `close.sh` soltando o escopo com os portões verdes, sem olhar a exigência → aceite 5.
- A palavra sozinha não lida em `principles` → aceite 6.
- A conferência de portões frescos retirada da aprovação → aceite 7.
- A regra do leitor para o gancho de prompt retirada → aceite 9.
- A linha `owner_approval: off` do dono ignorada pelo fecho → aceite 10.
- A exigência lida de um registro do livro em vez de valer por construção → aceite 21.
- O último plano guardado, em vez do primeiro não vazio → aceite 11.
- A linha no meio de frase aceita como ordem → aceite 14.
- O filtro do que já estava mexido retirado do fecho → aceite 15.
- Os portões permanentes fora do arquivo de portões da frente → aceite 16.
- O arquivo de portões permanentes fora da lista do dono → aceite 17.
- A eleição pelo arquivo nomeado depois do filtro por projeto → aceite 18.

## Out of scope

- A deduplicação das diretivas (protocolo, memórias, `CLAUDE.md`): frente seguinte, no monorepo
  NavBlue, quando esta versão estiver instalada. O texto das 26 regras já redigido para ela está no
  rascunho superado, que fica em disco.
- Reescrever o leitor de comandos (`hooks/shellread.py`).
- Três achados antigos sem frente, que o dono não pediu aqui: a cerca que não responde sem
  `python3`; o registro de aprovação com o nome do arquivo de modo de plano; e o pré-voo de plano
  novo lendo a base da frente anterior (este plano declara `base:` por causa dele).
- A bancada de sessão real (`tests/bench/bench.sh`) é ajustada ao fecho novo, mas não é rodada
  nesta frente: custa dinheiro e não está entre os portões.

## Overnight policy

- Decidido à noite, com fonte: nada; esta frente não roda sem o dono.
- Reservado ao dono: a aprovação do fecho, merge, push e a atualização do plugin instalado.

## Open questions

Nenhuma. As três do rascunho foram respondidas com "sim" pelo dono em 2026-11-13.

## Banca

base: 2f1b0ed
round: 2
sections-round1: Context | Risk band | Impact sweep (commands run now) | Changes, per file | Scope | Acceptance (EARS) | Verification (after the last commit) | Refutation | Out of scope | Overnight policy | Open questions
VERDICT: APPROVED

Revisor frio do plugin (`roadworthy:cold-reviewer`), duas rodadas em 2026-11-13, lendo pela base.

Rodada 1: REJECTED, quatro bloqueios, todos defeito do meu levantamento e todos mensuráveis antes
da banca. A classe do que faltou em cada um:

1. Não ataquei o canal que eu mesmo criei: o agente consegue rodar o gancho de prompt com um
   evento forjado e dar a "aprovação do dono". Corrigido na mudança 2 e no aceite 9.
2. Não segui quem escolhe o livro que um script lê: a exigência da aprovação viajava num registro
   que o agente desvia com uma variável de ambiente. Corrigido: ela vale por construção e só um
   arquivo do dono a dispensa (mudança 2, aceites 10 e 21).
3. Varri os consumidores com um padrão de texto que não casa com os cenários do simulador, e
   deixei o simulador e o fecho da madrugada lidos em parte; afirmei que nenhum teste mudava, e era
   falso. Corrigido na varredura, na mudança 2 e no aceite 22.
4. Não passei pelo meu desenho o caso que eu mesmo medi: com a sessão parada num subprojeto, a
   palavra do dono não acharia o item. Corrigido na mudança 2 e no aceite 6.

Rodada 2: APPROVED, nenhum bloqueio novo. Três avisos, aplicados sem rodada: a regra pela qual a
pasta da sessão acha a raiz do plano; o arquivo de exigências dos repositórios de brinquedo
commitado antes do fecho; e a lista de testes da varredura, que omitia um arquivo que só cita o
nome do script.

Não verificado pelo revisor, por não estar no repositório: as contagens tiradas das transcrições e
dos livros de negações (113, 43, 20, 8 e 13), medidas por mim nesta sessão; e a rodada verde da
suíte, que ele não rodou por ser somente leitura.
