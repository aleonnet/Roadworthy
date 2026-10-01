# Roadworthy — guia do desenvolvedor

[English](README_DEV.md) · **Português (Brasil)**

Para quem vai mudar o plugin, não usá-lo. Usar é o [`README.pt-BR.md`](README.pt-BR.md);
fazer uma tarefa passo a passo é o [`docs/guides/runbook.md`](docs/guides/runbook.md), em
inglês. Este arquivo explica como o plugin é construído e o que tem de continuar verdade
quando você o muda.

## Comece aqui

Você precisa de `bash` (3.2, o que o macOS traz, ou mais novo), `python3` (só a biblioteca
padrão) e `git`. `shellcheck` e a CLI `claude` são opcionais: a suíte pula o que falta e
avisa. Não há etapa de build nem nada para instalar.

```bash
bash tests/hooks/scope-lock.sh   # uma cerca, sozinha, em segundos: leia, é o padrão
bash tests/run.sh                # o portão inteiro, o mesmo que a CI roda; leva minutos
claude --plugin-dir .            # uma sessão real com ESTA árvore de trabalho como plugin
```

Depois leia um hook de cima a baixo — `protect-paths` é curto e traz o padrão inteiro — e
`hooks/lib.sh`, que todo hook carrega. O cabeçalho de cada hook diz o que ele garante, o
caso de campo que o moldou e como foi refutado. O detalhe mora lá, não aqui.

## A ideia

Regra escrita em prosa não segura um agente sob pressão; um hook que nega a chamada segura.
O Roadworthy embrulha uma unidade de trabalho num **rito**, e cada passo vira fato em disco:

```
sem frente --( plano aprovado no modo de plano )--> aprovação gravada
   ^                                                    |  scope-write.sh
   |  close.sh: todo portão verde                       v
   +------------- ou close.sh --abandon <--------- frente aberta
                                        (.roadworthy/scope, gates, plan.snapshot)
```

- Uma **frente** é um plano aprovado em execução: o escopo dele (globs), os portões dele
  (comandos) e uma fotografia do que foi aprovado, com digests.
- Os **hooks** julgam contra esse estado as chamadas que podem mudar alguma coisa — uma
  edição, um comando de shell, a saída do modo de plano — e o fim de um turno. Cada chamada é
  um processo novo: lê o evento que o Claude Code entrega como JSON no stdin, lê o disco,
  responde e sai. O que um hook lembra, ele lembra num arquivo.
- Os **scripts** são os únicos que escrevem o que uma frente É: escopo, portões, fotografia
  e estado. Nenhum hook abre ou fecha uma frente. Um hook só escreve o que viu: uma negação,
  uma aprovação, o veredito de um revisor.
- As **skills** e o agente `cold-reviewer` são instruções: dizem ao agente qual script rodar.
  Nada depende de o agente obedecer; os hooks valem quer ele obedeça, quer não.

Duas ideias explicam a maior parte do código. **Negar na porta o que dá para nomear, e pegar
o resto onde o conjunto é exato**: um leitor de comandos de shell não vê o que um
interpretador escreve, então para um arquivo comum o portão de entrada nega só um alvo que
consegue nomear, e o
commit (o próprio índice do git) e o fechamento (o diff da frente) recusam o que escapou. **A
evidência tem uma fonte que não é o agente**: a aprovação vem da pessoa aprovando o plano no
modo de plano, a revisão vem do relatório do próprio revisor, o portão vem do script que o
rodou — as duas últimas gravadas com a árvore sobre a qual foram medidas.

## Mapa do código

**Hooks** — `hooks/`, registrados em `hooks/hooks.json`, sem extensão de propósito.

- `session-state` — SessionStart; falha aberto. Diz o que está em disco. Não bloqueia.
- `principles` — UserPromptSubmit; falha aberto. Injeta as regras numeradas, a forma de
  relatar combinada para a frente e o aviso das três negações; grava a resposta `rw-human:`
  de uma pessoa.
- `rite-gate` — PreToolUse nas ferramentas de edição e no Bash; falha fechado. O portão de
  entrada: sem frente, nada é escrito; nada sob `.roadworthy/` à mão; a frente em disco é a
  que foi aprovada; o escopo vale também pelo shell.
- `protect-paths`, `scope-lock` — PreToolUse nas ferramentas de edição; falham fechados.
  Globs vedados; edição fora do escopo.
- `guard-commit`, `overnight-guard` — PreToolUse no Bash; falham fechados. O que um commit
  pode levar; o que espera a manhã.
- `plan-review-gate` — ExitPlanMode. Antes da chamada falha fechado: elege o plano que está
  sendo submetido e roda o pré-voo ou pede a banca. Depois da chamada grava a aprovação, e
  essa metade falha aberta; o portão de entrada consegue ler a mesma aprovação na
  transcrição da sessão.
- `review-record` — SubagentStop, e PostToolUse na ferramenta de entrega; nunca bloqueia.
  Grava o veredito do revisor frio de onde quer que o relatório chegue.
- `stop-gate` — Stop; nunca bloqueia por erro próprio. Bloqueia uma afirmação de "pronto"
  enquanto um portão não está fresco. O único hook que responde com exit 2.

**Código compartilhado** — também em `hooks/`.

- `hooks/lib.sh` — carregado por todo hook: lê o evento uma vez, `deny` e o livro de
  negações, a política de pane, a que repositório um caminho pertence, as listas do dono.
- `hooks/run-hook.cmd` — o lançador que o `hooks.json` chama; poliglota de batch e shell.
- `hooks/shellread.py` — lê um comando de shell do jeito que o shell lê e diz o que ele
  escreve e remove. O maior arquivo daqui; o contrato dele é uma tabela de casos.
- `hooks/globmatch.py` — a gramática de glob.
- `hooks/planblocks.py` — o que um plano declara (escopo, portões, base), a impressão digital
  dele, e se há uma aprovação dessa impressão digital gravada.
- `hooks/frontcheck.py` — a frente aberta está íntegra, o que mudou fora do escopo, de quem é
  o commit, o que este commit levaria.

**Scripts** — `skills/<skill>/scripts/`, as mãos do rito.

- plan: `scope-write.sh` abre uma frente; `plan-preflight.sh` confere um plano mecanicamente.
- close: `close.sh` roda os portões, grava a evidência, deriva o estado e libera o escopo;
  `tree-fingerprint.sh` nomeia a árvore sobre a qual um portão foi medido; `close-front.sh`
  move para o histórico os documentos de uma frente fechada.
- document: `docs-init.sh`, `docs-check.sh`, `pointers-check.sh`.
- refute: `refute.sh` planta um defeito e restaura por hash; `refute-ledger.sh` recusa uma
  cerca sem refutação registrada.
- resume: `resume-pick.sh`. overnight: `overnight-start.sh`, `overnight-entry.sh`,
  `overnight-close.sh`.
- `bin/rw-metrics` transforma uma rodada de evals em números.

**Estado em disco** — `.roadworthy/`, no projeto em que se trabalha.

- Do `scope-write.sh`: `scope` e `plan.snapshot` (locais), `gates` (rastreado: é commitado
  com a frente).
- Do `close.sh`: `state` e, em `evidence.jsonl`, cada portão que ele rodou, cada verificação
  humana e como cada fechamento terminou. Os hooks acrescentam ao mesmo livro as aprovações
  e os vereditos de revisor.
- Outros livros: `denials.jsonl`, `refutations.jsonl`, `preflight.jsonl`; `stop-latch/`; o
  marcador da madrugada `overnight`.
- Do dono, nunca do agente: `protected`, `free`, `rites`, `overnight-rules`, `docs.json`.

**Testes** — `tests/`, do estreito ao largo.

1. Casos: `tests/hooks/`, `tests/scripts/`, `tests/meta/`. Um arquivo por cerca ou script;
   entra um evento sintético e a resposta é julgada. `tests/cases.txt` é o manifesto.
2. O simulador, `tests/sim/rite-sim.py`: sessões inteiras por todo hook registrado, cada
   chamada executada num repositório de brinquedo quando nenhum hook a nega.
3. `tests/attack.sh`: tenta PASSAR pelas cercas. Cada ataque é `refused` ou `declared`.
4. `tests/bench/bench.sh`: uma sessão real sem interface. Custa dinheiro e não está no portão.
5. `evals/`: os mesmos prompts com e sem o plugin; veja `evals/README.md`.

## Invariantes

A maioria é uma ausência, e por isso é difícil de ver a partir de um arquivo só.

1. **Nenhuma cerca falha aberta.** Todo hook declara `RW_ON_CRASH` antes de carregar
   `hooks/lib.sh`. Com `deny`, um erro interno e uma saída antecipada do script — variável não
   definida, linha que o shell não lê — respondem com uma negação. Hook sem política declarada
   é, ele mesmo, um erro. Exceção: sem `python3` que rode, a cerca não responde nada.
2. **Uma negação é JSON no stdout com exit 0.** Entre os hooks só o `stop-gate` sai com 2,
   porque é assim que um hook de Stop bloqueia. O `principles` nunca pode: apagaria o prompt.
3. **A evidência de um projeto nunca vai para `CLAUDE_PLUGIN_DATA`.** Ela resolve por
   `rw_data_dir`: `ROADWORTHY_DATA` quando definida, senão o `.roadworthy/` do projeto.
   Aquela outra variável é compartilhada por todo projeto da máquina e não existe no shell de
   uma pessoa.
4. **Uma gramática para cada coisa; não acrescente cópia.** Globs, comandos de shell, blocos
   do plano e "de quem é a mudança" têm cada um o seu arquivo no código compartilhado acima.
   Leitores mais antigos ainda ficam ao lado deles e não são padrão: `overnight-guard` e
   partes do `guard-commit` casam o texto cru do comando; `plan-preflight.sh` e
   `plan-review-gate` leem sozinhos partes de um plano.
5. **O repositório que julga um arquivo é o repositório em que o arquivo está**
   (`rw_target_root`). Só um arquivo fora de qualquer repositório cai no da sessão.
6. **O agente não escreve nada à mão sob `.roadworthy/`.** Escopo, portões e fotografia vêm
   do `scope-write.sh`; o estado e os registros de portão, do `close.sh`; o que um hook
   presenciou, desse hook; os arquivos do dono, do dono (`docs-init.sh` cria o `docs.json`
   quando ele falta).
7. **Um ato de pessoa nunca é digitado pelo agente.** Abrir uma frente como dono (`--owner`)
   e responder a uma verificação humana são negados a ele.
8. **O fechamento mede o que foi aprovado**: uma frente que o rito abriu só fecha quando o
   escopo e os portões ainda casam com os digests da fotografia, e todo portão declarado
   roda ou o fechamento recusa.
9. **Nenhum caso fora do manifesto, nenhum caso que termina antes.** `tests/run.sh` recusa
   quando `tests/cases.txt` e os diretórios discordam, e um caso que não chega a `rw_end` é
   vermelho seja qual for o status de saída.
10. **Nada local é rastreado**: nenhum arquivo de estado local e nenhum caminho de home no
    que o git rastreia (`tests/meta/privacy.sh`).

## Preocupações transversais

- **Como um hook morre.** O Claude Code trata um código de saída não zero e diferente de 2
  como erro não bloqueante e deixa a chamada passar; por isso `hooks/lib.sh` vigia o trap de ERR
  (com `errtrace`, senão ele some dentro de funções) e também o de EXIT. Um comando cuja
  saída não zero é uma RESPOSTA (`close.sh --check`, o pré-voo) é chamado dentro de um `if`,
  com `set +o errtrace` em volta: copie o padrão do `stop-gate`.
- **Tempo.** Cada hook tem um `timeout` em `hooks/hooks.json`, e um hook que estoura o tempo
  não nega. Trabalho que custa por caminho tem teto ou é feito num processo só, e toda
  chamada paga por todo hook registrado nela: o evento é lido uma vez por chamada.
- **bash 3.2.** Não há `wait -n`. Um `case` dentro de `$( )` não é lido. Um apóstrofo sem par
  num heredoc dentro de `$( )` quebra o arquivo longe da causa; o `bash -n` de
  `tests/meta/hygiene.sh` pega. Num caso, que roda sob `set -euo pipefail`, um aborto por
  variável não definida chega ao trap de EXIT com status 0: daí o `rw_end`. Um hook roda só
  sob `set -u`, e ali o trap vê a falha.
- **Python dentro do shell.** A maior parte da lógica é Python em heredocs ou passado em linha
  com `-c`. `tests/meta/hygiene.sh` compila cada programa desses nos hooks e nos scripts e
  falha num import que ninguém usa. Mantenha bytecode fora da árvore: `sys.dont_write_bytecode`.
- **Caminhos.** O macOS entrega a um hook `/var/...` enquanto o git responde
  `/private/var/...`: resolva os dois lados com `rw_realpath` antes de comparar. Um glob é
  ancorado na raiz do repositório.
- **A lista dos arquivos de estado local é soletrada em muitos arquivos**: hooks, scripts, o
  instrumento dos evals, o arquivo de ignorados, vários casos e o simulador.
  `git grep -l 'refutations' -- hooks skills bin tests .gitignore` lista os arquivos que
  nomeiam um deles; abra cada um, e acrescente o arquivo de estado novo onde houver lista.
- **Opções e exigências.** Uma opção do usuário é `userConfig` em
  `.claude-plugin/plugin.json`, chega ao hook como `CLAUDE_PLUGIN_OPTION_<KEY>` e é lida com
  `rw_option`; uma sessão já aberta fica com o valor antigo até o `/reload-plugins`. O que um
  projeto exige mora no `.roadworthy/rites` dele, lido com `rw_rite`.
- **Windows.** `hooks/run-hook.cmd` entrega o hook ao Git Bash. Sem bash ele recusa: exit 2
  para uma cerca, exit 1 para os quatro hooks que não podem bloquear. Esse ramo só roda na
  CI (`.github/workflows/ci.yml`, job `windows-no-bash`).
- **Duas línguas.** Planos, bancas e palavras de status são lidos em inglês e em português
  (`Scope` ou `Escopo`, `VERDICT` ou `VEREDITO`), e o `README.md` tem um gêmeo em português
  mantido em passo por um portão — como este arquivo tem o dele.

## Como mudar

Toda mudança neste repositório passa pelo rito do próprio plugin — plano, aprovação, frente,
fechamento — e o runbook traz os passos. O que tocar junto:

- **O comportamento de um hook.** Primeiro a asserção que reprova, no caso dele em
  `tests/hooks/`. Depois o hook. Refute a verificação nova uma vez com `refute.sh` e escreva
  a linha `Refuted` datada no cabeçalho do hook: um portão a lê. Se a mudança fecha um
  contorno, acrescente o ataque em `tests/attack.sh`; se muda uma garantia, os dois READMEs e
  o CHANGELOG.
- **Um hook novo.** Um arquivo sem extensão em `hooks/` que exporta `RW_HOOK` e
  `RW_ON_CRASH`, carrega `hooks/lib.sh` e chama `rw_read_event`; uma entrada com `timeout` em
  `hooks/hooks.json`; um caso, e a linha dele em `tests/cases.txt`; o nome dele em
  `RW_FENCES` (`tests/meta/hygiene.sh`), no `--sources` do portão do livro de refutações, no
  ramo sem bash de `hooks/run-hook.cmd` se ele não pode bloquear, nos dois READMEs, e no mapa
  do código acima — um portão recusa um hook ou um script que este arquivo não nomeia.
- **Uma opção nova.** `userConfig` em `.claude-plugin/plugin.json`, `rw_option KEY default`
  no hook, a tabela de configuração dos dois READMEs, e um caso nas duas direções.
- **Um comando que o leitor lê errado.** Primeiro uma linha na tabela de
  `tests/scripts/shellread.sh` — a tabela é o contrato do leitor — e só então
  `hooks/shellread.py`.
- **Um caso novo.** Um arquivo que carrega `tests/lib.sh`, monta as próprias fixtures
  (`tests/fixtures/`) e termina com `rw_end`, mais a linha dele em `tests/cases.txt`. Capture
  a saída numa variável antes de casá-la: sob `pipefail`, `cmd | grep -q` fica vermelho
  quando o produtor escreve qualquer coisa depois do casamento.
- **Um cenário novo.** Um arquivo JSON em `tests/sim/scenarios/`: `live-*` para trabalho
  honesto, em que um passo negado é um beco sem saída; `att-*` para uma tentativa de passar
  pelo rito.
- **Refutação é uma vez por garantia, quando ela nasce.** Depois a suíte a carrega.
- **Uma versão.** Os dois manifestos e o CHANGELOG andam juntos, e um portão confere.

## Onde ler depois

- `README.pt-BR.md` — o que cada hook garante, toda opção, os limites declarados. É a
  referência; este arquivo aponta para ela em vez de repeti-la.
- `docs/README.md` — o mapa de `docs/`. Os registros em `docs/decisions/` dizem por que as
  coisas são como são, cada um com a medição por trás.
- `docs/reference/roadmap.md` — o feito, o pendente e os limites aceitos de propósito. Leia
  "Declared limits" antes de consertar um.
- `docs/guides/runbook.md` — como fazer cada tarefa recorrente, e o que fazer quando falha.
- A documentação do próprio Claude Code, para o que um hook recebe e o que os códigos de
  saída dele significam: <https://code.claude.com/docs/en/hooks> e
  <https://code.claude.com/docs/en/plugins/create>.

A forma deste arquivo é a que matklad descreve para um `ARCHITECTURE.md` — curto, um mapa do
código, invariantes, preocupações transversais, nomes em vez de links
(<https://matklad.github.io/2021/02/06/ARCHITECTURE.md.html>) — e o runbook é um guia de como
fazer no sentido do Diátaxis (<https://diataxis.fr/how-to-guides/>).
