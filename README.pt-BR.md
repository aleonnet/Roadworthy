# Roadworthy

[English](README.md) · **Português (Brasil)**

**Uma mudança, zero dano colateral.**

## TL;DR

Roadworthy é um plugin do Claude Code que transforma regras de qualidade em hooks. Um agente que
mexe em código faz uma coisa bonita e quebra outras dez; prosa não impede isso, um hook que nega a
edição impede.

- **Sem frente aberta, nada é escrito.** Até um plano aprovado declarar o escopo, toda edição e
  toda escrita pelo shell dentro do repositório é negada, nomeando o rito que abre uma frente.
- **Escopo declarado, escopo imposto.** Editar, ou escrever pelo shell num alvo nomeado, fora dos
  globs declarados é negado; um commit só leva o que a frente declarou; e o fechamento recusa uma
  frente cujo diff saiu deles.
- **Nada de "pronto" sem prova.** Um turno que afirma ter terminado é bloqueado até todo portão
  declarado ter rodado, fresco, sobre o último commit.
- **Commits limpos.** Sem flags proibidas, sem commit vazio; à noite sem push, merge nem tag, e os
  arquivos que o projeto declara congelados seguem congelados.

Dois comandos para instalar, quatro passos até a primeira frente, um arquivo para declarar a sua
régua de qualidade (`.roadworthy/gates`). Custo: cerca de 772 tokens a cada prompt, medido com
`claude plugin details`. Construído sobre o formato oficial de plugins: hooks, skills, agentes,
configuração do usuário. Sem daemon, sem enxame, sem framework para aprender.

## Instalação

```bash
claude plugin marketplace add aleonnet/Roadworthy
claude plugin install roadworthy@roadworthy
```

O Claude Code pergunta as [opções](#configuração) ao habilitar. Rodar os dois comandos de novo é
idempotente; `claude plugin update roadworthy@roadworthy` pega versões novas, e `/reload-plugins`
aplica uma opção alterada sem perder a conversa.

## A primeira frente

1. **Planejar.** `/roadworthy:plan` escreve um plano com o **Escopo** (globs) e a **Verificação**
   (comandos dos portões) em blocos cercados, combina com você como a frente vai relatar
   (`report:`), e `plan-preflight.sh` confere o plano mecanicamente antes que alguém o leia. Você o
   aprova no modo de plano, e a aprovação fica registrada.
2. **Abrir.** `scope-write.sh <plano.md>` escreve `.roadworthy/scope`, `.roadworthy/gates` e a
   fotografia da aprovação num só ato — a partir do plano que você aprovou, e de nenhum outro. Daqui
   em diante as cercas estão ligadas.
3. **Trabalhar.** Edições e escritas nomeadas pelo shell fora do escopo são negadas; o próprio
   arquivo do plano continua editável. Os commits só levam o que o escopo cobre.
4. **Fechar.** Escreva e commite o handoff; então `/roadworthy:close` roda os portões depois do
   último commit, grava cada um com a impressão digital da árvore e libera o escopo. Só então o
   turno pode dizer "pronto".

## O que ele impõe (hooks)

| Hook | Evento | Garantia |
|---|---|---|
| `session-state` | início de sessão | Diz o que o rito deixou em disco: ramo, árvore, frente aberta e o plano dela, estado gravado, o que espera uma pessoa, o que o dono exige, o marcador da madrugada, se os portões estão frescos. Fatos, nunca um veredito. |
| `principles` | todo prompt | Injeta os seus princípios numerados e as regras numeradas do projeto, fixa o arquivo de princípios por digest, repete a forma de relatar combinada para a frente aberta e grava a resposta de uma pessoa a uma verificação humana. |
| `rite-gate` | Edit/Write **e Bash** | Sem frente aprovada, nenhuma escrita dentro do repositório. Os arquivos do próprio rito são escritos pelos scripts dele e por mais nada; os cinco arquivos do dono são do dono. Com frente aberta, uma escrita nomeada pelo shell fora do escopo é negada. |
| `scope-lock` | Edit/Write | Enquanto existe um escopo, uma edição fora dos globs dele é negada — o escopo do repositório em que o arquivo está. |
| `protect-paths` | Edit/Write | Caminhos que casam com `protected_paths` (e com o `.roadworthy/protected` do projeto) nunca são editados. |
| `guard-commit` | Bash | Um `git commit` é negado com flag proibida (padrão `--trailer`), sem nada em stage, ou quando levaria um caminho vedado ou um caminho fora do escopo da frente aberta. |
| `plan-review-gate` | ExitPlanMode | Um plano sai do modo de plano só quando o pré-voo está verde e, onde o usuário ou o projeto pedem, uma banca fria diz `VERDICT: APPROVED`. Quando você aprova o plano, a aprovação é gravada. |
| `review-record` | fim de subagente | Grava o veredito do revisor frio com o commit sobre o qual ele foi dado, para que "uma revisão aprovou isto" tenha uma fonte que não seja o agente. |
| `stop-gate` | Stop | Uma afirmação de que o trabalho terminou é bloqueada enquanto `close.sh --check` não reporta todo portão declarado como FRESH, em todo repositório em que o turno escreveu. |
| `overnight-guard` | Bash | Enquanto `.roadworthy/overnight` existe, push, merge, tag, `gh pr merge` e as regras `deny:` do projeto são negados. |

<details>
<summary><strong>A letra miúda, hook por hook</strong> — o que cada um mede, e o caso de campo que o moldou</summary>

**`session-state`.** Quando uma sessão começa, retoma, é limpa ou é compactada dentro de um
repositório, a primeira coisa no contexto dela é o que está em disco: o ramo e a distância dele para
o remoto, a árvore, a frente aberta (de qual plano, desde quando, de qual base), a forma de relatar
combinada para ela, o estado gravado, o que espera uma pessoa, o que o dono exige
(`.roadworthy/rites`), o marcador da madrugada e se os portões declarados estão frescos. Moldado
por uma sessão que retomou no ramo errado sem que nada avisasse. Não consegue bloquear.

**`principles`.** Injeta os seus princípios numerados (o conjunto embutido ou o seu próprio arquivo)
mais as regras numeradas da memória do projeto atual, para que nunca percam saliência numa sessão
longa. Também **fixa o arquivo de princípios por digest**: o arquivo vive fora de todo repositório,
então nada impede que seja editado — o que isto faz é anunciar a mudança a cada prompt, nomeando o
digest e a data do último acordo, até você concordar com o texto novo. Enquanto uma frente está
aberta, repete a **forma de relatar** que o plano combinou (`report:`). Quando a mesma cerca negou
**do mesmo jeito três vezes** — o agente principal desta sessão, com escopo aberto, desde a abertura
da frente — isso volta como uma linha no prompt, e a terceira negação já o diz no próprio motivo. E
é onde **uma pessoa responde a uma verificação humana**: uma linha `rw-human: all approved` (ou
`rw-human: <item> rejected <nota>`) no seu próprio prompt é gravada; o mesmo comando digitado pelo
agente é negado.

**`rite-gate`.** Enquanto o repositório **em que o alvo está** não tem um `.roadworthy/scope`
utilizável, toda edição, escrita pelo shell e remoção pelo shell de conteúdo rastreado ali é negada,
nomeando o rito que abre uma frente. Um arquivo de escopo **vazio** não conta. Os comandos de shell
são lidos por `hooks/shellread.py` do jeito que o shell os lê — aspas, heredocs, substituições, todo
separador, invólucros, `bash -c`, o diretório em vigor — e a gramática dele é uma tabela de casos
(`tests/scripts/shellread.sh`). **A frente só abre do que você aprovou:** quando o agente roda
`scope-write.sh`, o escopo, os portões e a base do plano precisam casar com uma aprovação
registrada; o dono abre uma ele mesmo, num shell dele, com `scope-write.sh <plano.md> --owner`, que
é negado ao agente. **O diretório do próprio rito é fechado a tudo que não sejam os scripts dele:** um
caminho sob `.roadworthy/` só pode ser entregue a um comando conhecido por ler; escrever, remover,
varrer (`find -delete`, `git clean`), um interpretador cujo código escreve ali, e o mesmo diretório
escrito com outra caixa são negados. Os cinco arquivos do dono — `protected`, `free`, `rites`,
`overnight-rules`, `docs.json` — são do dono. **Com uma frente aberta**, uma escrita nomeada pelo
shell fora do escopo é negada como uma edição, um caminho vedado é vedado também pelo shell, uma
frente cujo escopo ou cujos portões já não casam com a fotografia da aprovação para toda escrita até
ser reaberta, e uma mudança fora do escopo que algum programa deixou na árvore é **dita** ao agente
(é no commit e no fechamento que ela é recusada). O que não precisa de frente: o plano (um `.md`
direto num dos seus dois lares), a pasta temporária da sessão, a memória do projeto, o que o git
ignora e os caminhos que o dono lista em `.roadworthy/free`. Medido neste repositório em
2026-09-13: 60 edições e 117 comandos de shell num dia, zero invocações do rito, ninguém notou.

**`scope-lock`.** Enquanto `.roadworthy/scope` existe no repositório em que o arquivo está, qualquer
edição fora dos globs listados é negada. O escopo que conta é o daquele repositório, nunca o do
repositório em que a sessão por acaso está; um arquivo fora de qualquer repositório, sob um
diretório temporário, não é projeto de ninguém. O próprio arquivo do plano (um `.md` direto em
qualquer dos seus dois lares) é isento: é o artefato do rito. O shell é a porta do portão de
entrada, para os alvos que um leitor de comandos consegue nomear; o que um programa escreve sozinho
é pego onde o conjunto é exato — no commit e no fechamento. Veja
[Limites declarados](docs/reference/roadmap.md).

**`protect-paths`.** Caminhos que casam com `protected_paths` nunca são editados, decida o modelo o
que decidir.

**`guard-commit`.** `git commit` com uma flag proibida (padrão `--trailer`) ou sem nada em stage é
negado. E **o que entra no histórico é o que a frente declarou**: o conjunto que um commit levaria é
lido do próprio índice do git — o que está em stage, o que o mesmo comando põe em stage, toda
mudança rastreada quando ele diz `-a` — e o commit é negado quando esse conjunto traz um caminho
vedado, um caminho fora do escopo da frente aberta ou, sem frente aberta, qualquer coisa que não
seja o plano, `.roadworthy/gates` e o que o dono liberou. Vale seja qual for o meio pelo qual o
arquivo foi escrito, que é o que o portão de entrada não consegue prometer sobre um programa que
abre arquivos sozinho. `commit_scope=false` desliga.

**`plan-review-gate`.** O que guarda um plano é `plan_gate`. Em `preflight` (o padrão desde 0.6.0)
o plano é conferido mecanicamente por `skills/plan/scripts/plan-preflight.sh` e a submissão é negada
com essa saída quando está vermelha — citações que a linha não sustenta, caminhos de escopo que não
existem, números de aceite com lacuna, uma correção declarada cujo texto antigo ainda está lá, e um
arquivo do escopo que nunca foi lido INTEIRO na sessão, provado pela transcrição que o harness
escreve. Cinco rodadas de banca fria sobre um plano nunca convergiram aqui, e a causa medida foi que
cada rodada gastava a atenção em coisas que uma máquina confere; o revisor volta para o diff, que é
o que o princípio 4 sempre disse. Em `review` (e `both`) um plano só pode ser submetido com uma
banca que diga `VERDICT: APPROVED` — ao lado dele como `<plano><review_suffix>` ou, no modo de plano
onde só um arquivo pode ser escrito, como uma seção `## Review` do próprio plano. REJECTED e
ESCALATE negam, a rodada 3 exige a decisão `owner:` do usuário, e uma seção acrescentada depois da
rodada 1 nega (guarda de crescimento). O plano tem dois lares e o portão lê os dois: `plans_dir`
(compartilhado por todo projeto) e o diretório `plans` do `.roadworthy/docs.json`. O plano declara
`project:` e o portão elege por isso, nomeia um plano que pertence a outro lugar, pula um marcado
como superado e recusa dois planos vivos de um projeto em vez de escolher por data. Quando a chamada
traz o texto do plano, o texto escolhe o arquivo; quando nada casa byte a byte, o plano que esta
sessão escreveu por último (pela transcrição) é eleito; só então o mais novo por data — e o portão
diz isso no contexto que devolve. Um plano pode declarar `base:`; a ref precisa resolver e a banca
precisa nomear a mesma. **O projeto pode pedir mais do que a sua opção pede:** uma linha
`plan_gate:` em `.roadworthy/rites` é somada à opção e vale a mais rígida, de modo que um projeto
cujo dono quer todo plano revisado não depende de uma nota que o agente pode não abrir. E **quando
você aprova o plano, a aprovação é escrita** — a impressão digital do escopo, dos portões e da base
dele —, que é o que o portão de entrada procura antes de uma frente abrir. Editar a prosa depois
mantém a aprovação; mudar um glob, um portão ou a base pede outra.

**`review-record`.** Quando o agente `cold-reviewer` termina com uma linha `VERDICT:`, o veredito é
gravado com o commit e a árvore sobre os quais foi dado. Com `diff_review: required` em
`.roadworthy/rites`, o fechamento só passa com um veredito APPROVED para o commit que está sendo
fechado; onde um plano precisa de banca (`plan_gate` em `review` ou `both`), o arquivo da banca
precisa ter por trás o veredito do próprio revisor, gravado pelo plugin.

**`stop-gate`.** Um turno que diz que o trabalho terminou é bloqueado enquanto `close.sh --check`
não reporta todo portão declarado como FRESH, e o bloqueio mostra o estado de cada um — no
repositório em que a sessão está e em todo outro em que ela escreveu. Ele julga uma **afirmação**,
não uma palavra: a palavra não conta numa linha de tabela, numa legenda de marcas de status, negada,
nem seguida de "para/quando/se", e uma mensagem que nomeia o que ainda está em aberto
(`stop_gate_open_markers`) é um relato de estado, não uma afirmação. **Nunca
bloqueia um projeto sem arquivo de portões** (essa verificação falha ali de propósito), nunca
bloqueia a mesma árvore duas vezes — a trava é chaveada pelo conteúdo da árvore, então uma árvore
alterada é julgada de novo —, honra o campo documentado `stop_hook_active` e falha aberto em
qualquer coisa que não consiga ler. Lê a evidência do próprio projeto, no ambiente que o Claude Code
dá a um hook (medido em 2026-09-14: seis portões FRESH foram reportados como MISSING porque o
livro-razão era resolvido por um diretório compartilhado pelos projetos de todo plugin). Exit 2 é o
que bloqueia um turno; o evento Stop tem contrato próprio.

**`overnight-guard`.** Enquanto `.roadworthy/overnight` existe (posto por `/roadworthy:overnight`
por ordem do usuário), `git push`, `git merge`, `git tag`, `gh pr merge` e toda regra `deny:` de
`.roadworthy/overnight-rules` são negados; `protect-paths` também congela os globs `freeze:` do
mesmo arquivo.

</details>

<details>
<summary><strong>Como um hook falha, onde mora a evidência, Windows</strong></summary>

Todo hook declara a sua política de pane. As seis cercas (`rite-gate`, `scope-lock`,
`protect-paths`, `guard-commit`, `overnight-guard`, `plan-review-gate`) **falham fechadas**: um erro
interno nega a ação, porque uma fronteira que falha aberta não é fronteira — e o mesmo vale para uma
cerca que simplesmente morre (uma variável não definida, uma linha que o shell não consegue ler), o
que antes deixava a chamada passar. O hook `principles` falha aberto com um aviso visível, porque um
erro na submissão do prompt jamais pode apagar o prompt; `stop-gate`, `session-state` e
`review-record` também falham abertos, porque uma sessão que não consegue terminar, não consegue
começar, ou um subagente que não consegue parar é a falha mais cara. Negações são decisões JSON
estruturadas, nunca um exit 2 seco — exceto no `stop-gate`, onde exit 2 é a forma que o evento Stop
tem de bloquear um turno. **Toda negação é registrada** em `.roadworthy/denials.jsonl` com a cerca,
o motivo, a sessão, o subagente quando há um, e se havia escopo aberto — no repositório em que o
alvo negado está, e nunca criando esse diretório num repositório que não o tem.

**Onde mora a evidência.** Livros-razão, trava, estado e registros de refutação vão para
`ROADWORTHY_DATA` quando a variável está definida, senão para `<repositório>/.roadworthy`. Não para
`CLAUDE_PLUGIN_DATA`: o Claude Code a define, para todo hook, como um diretório por plugin,
compartilhado por todo projeto da máquina, e o shell de uma pessoa não a define — quem escreve e
quem lê nunca se encontrariam (medido em 2026-09-14). A única coisa guardada lá é o pino do arquivo
de princípios, que vive fora de todo repositório.

**No Windows sem bash**, `hooks/run-hook.cmd` recusa em vez de deixar a chamada passar sem guarda:
uma cerca sai com 2 e o motivo no stderr; `principles`, `stop-gate`, `session-state` e
`review-record` avisam com exit 1. Executado num runner Windows na CI; não executado na máquina que
o escreveu.

**Custo**, medido com `claude plugin details` em 2026-09-14: cerca de 772 tokens sempre ligados; 310
a 3.700 por invocação de skill ou agente (a skill de plano é a de 3.700).

</details>

## O que ele ensina (skills)

| Skill | Uso |
|---|---|
| `/roadworthy:plan` | Um plano que nasce pronto: leitura de arquivo inteiro, varredura de impacto com comandos, aceite em EARS, escopo em globs, e `plan-preflight.sh` conferindo o que um leitor jamais deveria gastar atenção. |
| `/roadworthy:refute` | Provar que uma verificação pode falhar: injetar o defeito, esperar o texto da falha, restaurar byte a byte, conferir o hash. Uma vez por garantia, quando ela nasce. |
| `/roadworthy:close` | Rodar os portões declarados depois do último commit, gravar cada um com a impressão digital da árvore, liberar o escopo. |
| `/roadworthy:document` | Registros de decisão datados, vocabulário de status MADR, revisão por arquivo novo, uma seção de Confirmação e os verificadores que mantêm a árvore honesta. |
| `/roadworthy:resume` | Retomar do disco: o mapa, o handoff mais novo por nome, o estado confirmado por comando. |
| `/roadworthy:overnight` | Execução sem supervisão de um plano aprovado, só por ordem do usuário: um diário com horas tiradas por script, publicação congelada até de manhã, um handoff para auditar ao acordar. |

E um agente, `cold-reviewer`: só leitura, vê apenas o diff ou o plano e os critérios, reporta só o
que afeta a corretude, falha fechado.

<details>
<summary><strong>O que cada skill roda</strong></summary>

- **plan** — `[NEEDS CLARIFICATION]` em vez de suposições; uma pergunta sobre como a frente vai
  relatar, escrita na linha `report:` do plano; `scope-write.sh` abre a frente a partir dos blocos
  cercados do plano, mantém a base quando a mesma frente é reaberta e recusa uma segunda frente
  sobre uma viva; `plan-preflight.sh` confere citações por conteúdo, caminhos do escopo, numeração
  do aceite, correções declaradas e leitura de arquivo inteiro provada pela transcrição.
- **refute** — `skills/refute/scripts/refute.sh` faz isso mecanicamente e escreve o registro. Uma
  refutação roda a sua verificação duas vezes, então doze delas custam doze rodadas da suíte: uma
  vez por garantia, não a suíte inteira a cada mudança.
- **close** — `close.sh` roda todo portão de `.roadworthy/gates` com a entrada isolada e recusa
  quando rodaram menos do que os declarados; diz FRESH/STALE/MISSING depois com `--check`; recusa
  uma frente cujo diff tocou um caminho vedado ou saiu do escopo. A verificação humana tem estado
  próprio: `--needs-human "<item>"` abre uma, `--human` lista as abertas, a resposta da pessoa a
  fecha, e nenhum fechamento posterior a apaga. `--abandon "<motivo>"` encerra, com registro, uma
  frente sem caminho adiante. `close-front.sh` move uma frente fechada para o histórico com os
  links reescritos.
- **document** — `docs-init.sh` monta a árvore por papel, `docs-check.sh` e `pointers-check.sh` a
  mantêm honesta. Projetos que escrevem as palavras de status em outra língua as declaram sob
  `status` em `.roadworthy/docs.json`.
- **resume** — `resume-pick.sh` escolhe o handoff pelo nome, nunca pela data de modificação, e
  segue `superseded by`.
- **overnight** — alguns times rodam o agente sem supervisão sobre um plano aprovado e auditam o
  resultado de manhã, na coisa real; isto torna essa rotina mecânica. Começa só por ordem explícita
  do usuário: `overnight-start.sh` confere a banca aprovada (por nome) e a política da madrugada do
  plano, listando de uma vez toda pré-condição faltante; `overnight-entry.sh` registra decisões com
  fonte primária, commits de fase e bloqueios, e o diário não pode carregar hora estimada; publicar
  é negado até o marcador ser removido; `overnight-close.sh` exige todo portão FRESH e escreve o
  handoff da manhã com a tabela de bancada que o usuário preenche. Congelamentos por projeto vivem
  em `.roadworthy/overnight-rules` (`deny: <regex>` para comandos, `freeze: <glob>` para arquivos).
  Registro: `docs/decisions/2026-09-03-1322-overnight-mode.md`.

</details>

## Configuração

Definida ao habilitar, ou depois com `/plugin` → Roadworthy → Configure. Os valores chegam aos
hooks como variáveis de ambiente `CLAUDE_PLUGIN_OPTION_<CHAVE>`.

| Opção | Padrão | Significado |
|---|---|---|
| `principles_file` | `principles/PRINCIPLES.md` embutido | Arquivo Markdown cujas linhas numeradas são injetadas a cada prompt. |
| `project_rules` | `true` | Injetar também as linhas numeradas do `MEMORY.md` da memória automática do projeto. |
| `protected_paths` | vazio | Globs separados por vírgula que Edit/Write jamais podem tocar; o projeto pode acrescentar os seus em `.roadworthy/protected`, que o dono edita fora do agente. |
| `stop_gate` | `true` | Bloquear uma afirmação de "pronto" enquanto um portão declarado não está FRESH. |
| `stop_gate_open_markers` | marcas de status, `TODO`, "ainda falta", "em andamento" | Marcas separadas por vírgula; uma mensagem final que traz uma delas fora de uma linha de legenda nomeia um item em aberto e não é julgada como afirmação de "pronto". |
| `session_state` | `true` | Dizer o estado em disco quando uma sessão começa, retoma, é limpa ou é compactada. |
| `rite_gate` | `true` | Negar edições e escritas pelo shell enquanto nenhuma frente está aberta, e negar escritas nos arquivos que só um script pode escrever. |
| `scope_lock` | `true` | Honrar `.roadworthy/scope`. |
| `forbidden_commit_flags` | `--trailer` | Flags separadas por vírgula negadas em comandos de commit. |
| `block_empty_commits` | `true` | Negar `git commit` sem nada em stage. |
| `commit_scope` | `true` | Negar um commit que levaria um caminho vedado, um caminho fora do escopo da frente aberta ou — sem frente aberta — qualquer coisa que não sejam os artefatos do próprio rito. |
| `plan_gate` | `preflight` | O que guarda um plano: `preflight` confere mecanicamente; `review` é o veredito adversarial anterior à 0.6.0; `both` são os dois. |
| `plan_review_required` | `true` | Exigir a banca antes do ExitPlanMode. Ela se liga ao plano por nome, nunca por hash: o que o usuário aprovou é o que conta. |
| `max_review_rounds` | `2` | Rodadas de banca fria que um plano pode ter antes que só a decisão escrita do usuário (uma linha `owner:`) o destrave. A rodada 3 não existe. |
| `review_suffix` | `.review.md` | Sufixo do arquivo de banca ao lado do plano. |
| `plans_dir` | `~/.claude/plans` | Onde o Claude Code escreve os planos do modo de plano. Compartilhado por todo projeto, então um plano declara `project:` no cabeçalho. O segundo lar é o diretório `plans` do `.roadworthy/docs.json`. |

**Uma opção alterada não chega a uma sessão que já está aberta.** O Claude Code lê as opções ao
carregar o plugin, então depois de mudar uma rode **`/reload-plugins`** ou abra uma sessão nova.
Medido em 2026-09-13: a opção estava certa no disco, o hook a honrou quando a variável chegou até
ele, e a sessão aberta seguia negando com o valor antigo.

<details>
<summary><strong>O que o projeto declara</strong> — os arquivos sob <code>.roadworthy/</code> que são seus</summary>

As opções acima são do usuário e nascem permissivas. O que um PROJETO exige mora no projeto, em
arquivos que o agente lê e não consegue editar nem remover (um glob ou um `chave: valor` por linha,
`#` começa um comentário):

| Arquivo | O que diz |
|---|---|
| `.roadworthy/gates` | Os comandos que um fechamento roda, um por linha. Escrito por `scope-write.sh` a partir do bloco de Verificação do plano e versionado como um teste. |
| `.roadworthy/protected` | Globs que ninguém edita, por nenhuma porta: as ferramentas de edição, o shell, o commit, o fechamento. |
| `.roadworthy/free` | Globs que não pedem frente nem escopo: notas privadas, rascunhos, uma área de rascunho dentro do repositório. |
| `.roadworthy/rites` | O que este projeto exige além dos padrões do plugin: `plan_gate: preflight\|review\|both`, `diff_review: required`. Uma palavra que ele não conhece recusa, em vez de significar "sem exigência". |
| `.roadworthy/overnight-rules` | `deny: <regex>` para comandos e `freeze: <glob>` para arquivos enquanto o marcador da madrugada existe. |
| `.roadworthy/docs.json` | O mapa da documentação, as palavras de status e o diretório `plans`. |

Todo o resto ali (`scope`, `plan.snapshot`, `state`, os livros-razão `.jsonl`) é o estado local do
rito: escrito pelos scripts dele, ignorado pelo git no seu clone desde o momento em que uma frente
abre, e nunca editado à mão.

</details>

## Testes

```bash
bash tests/run.sh              # o portão inteiro: 34 casos, ~9 min
bash tests/hooks/scope-lock.sh # uma cerca, sozinha, em segundos
bash tests/attack.sh           # a suíte de trapaças: 148 ataques, 132 recusados, 16 declarados
bash tests/bench/bench.sh      # as cercas diante de uma sessão REAL, sem interface (gasta alguns centavos)
```

Todo hook é exercitado com JSON real no stdin nas duas direções, todo script é refutado com uma
verificação de brinquedo, todo bloco Python embutido no shell é compilado e conferido contra imports
mortos, os manifestos são validados com `claude plugin validate --strict`, e uma varredura de
privacidade falha em qualquer caminho absoluto de home. A CI roda `tests/run.sh` em macOS e Linux,
executa o ramo sem bash do `run-hook.cmd` no Windows e pode rodar o único caso de eval que exige
Bash no Linux.

<details>
<summary><strong>Como a suíte é feita, e por quê</strong></summary>

**Entre as duas fica o simulador.** `tests/sim/rite-sim.py` conduz sessões inteiras — chamada de
ferramenta após chamada de ferramenta — por todo hook que o `hooks.json` registra, executa cada
chamada num repositório de brinquedo quando nenhum hook a nega, e depois pergunta ao repositório o
que aconteceu. `tests/meta/rite-liveness.sh` roda os cenários dele em dois tipos: um agente honesto,
estado após estado, em que um passo negado que deveria ter passado é um **beco sem saída**; e um
agente tentando passar pelo rito, em que nada do que o rito proíbe pode ser verdade no fim. A
primeira rodada dele achou uma escrita pelo shell fora do escopo passando com frente aberta, e
`git commit -am` recusado como commit vazio.

**A suíte dispara eventos sintéticos; a bancada dispara uma sessão.** `tests/bench/bench.sh` carrega
os hooks da árvore de trabalho em `claude -p --plugin-dir` sobre um repositório de brinquedo, um ato
exato por prompt, e lê os próprios `permission_denials` do harness e o disco: sem frente → edição
negada; o agente abrindo uma frente de um plano que ninguém aprovou → negado; o dono a abre; escrita
pelo shell e edição fora do escopo negadas; `rm .roadworthy/plan.snapshot` negado; afirmação de
"pronto" sobre portões FRESH não bloqueada; negações no livro-razão do projeto. Toda
versão antes da 0.6.1 saiu "provada pela suíte, não provada em campo"; isto é o campo.

| Onde | O quê |
|---|---|
| `tests/run.sh` | o executor: lê `tests/cases.txt`, roda cada caso (quatro por vez), incorpora a suíte de ataques |
| `tests/cases.txt` | **o manifesto, e a cerca.** Um executor que varre um diretório perde um caso no dia em que o arquivo é apagado e não diz nada; este recusa rodar quando a lista e o diretório discordam, em qualquer direção |
| `tests/lib.sh` | `ok`/`fail`, `run_hook`, `denied`, `golden`, a raiz temporária e `rw_end` |
| `tests/hooks/`, `tests/scripts/`, `tests/meta/` | um caso por cerca, por script e para a higiene da própria suíte |
| `tests/fixtures/` | os repositórios de brinquedo, árvores de documentação, planos e transcrições, construídos por nome |
| `tests/goldens/` | os envelopes de negação e de contexto, comparados chave a chave |
| `tests/sim/` | o simulador de sessão e os cenários dele (`live-*` trabalho honesto, `att-*` tentativas de passar pelo rito) |
| `tests/bench/` | a bancada de sessão real sem interface, e o que cada passo prova |

**Um caso é um arquivo que você roda sozinho, e esse é o ponto.** Uma refutação prova que uma cerca
consegue ficar vermelha injetando o defeito e rodando a verificação duas vezes. Contra um monólito
de 1407 linhas isso custava duas rodadas inteiras da suíte; medido neste repositório, as seis
refutações do `plan-preflight.sh` levaram 32 minutos de relógio. Contra um caso: 5,3 segundos.

**Um caso que morre antes da última asserção é vermelho, por construção.** `rw_end` levanta uma
bandeira e o handler de saída se recusa a reportar sucesso sem ela. Medido no bash 3.2, uma
variável não definida sob `set -u` aborta o script e o trap `EXIT` vê `$?=0`, então o caso sai com
**0** com metade das asserções nunca rodadas — que é o que `tests/run.sh` carregava antes de isto
ser achado, pela suíte, nela mesma.

**Esta suíte é o que você roda a cada mudança; a refutação não é.** Uma refutação existe para
provar que uma cerca nova consegue ficar vermelha pelo motivo dela, então pertence ao momento em que
a cerca é escrita — uma vez, registrada no cabeçalho da verificação — e depois disso a suíte a
carrega.

</details>

## Evals

`evals/` guarda sete casos que medem as cercas com e sem o plugin sobre os mesmos prompts;
`bin/rw-metrics` transforma a rodada em sete KPIs (sucesso na tarefa, regressão, arquivos fora do
escopo, falso sucesso, negações, tokens, turnos). Os avaliadores julgam os bytes dos arquivos e a
linha final `STATUS:`, nunca a tentativa. Medido com um modelo menor (`--model haiku`) em
2026-09-14: veja `evals/README.md` e `docs/decisions/2026-09-14-1750-evals-com-modelo-menor.md`.

## Limites declarados

O Roadworthy fecha os caminhos que um agente toma por descuido ou por atalho. Ele não afirma parar
um agente que se propõe a derrotá-lo, e o motivo é estrutural: o agente e os hooks rodam como o
mesmo usuário, então o que um hook consegue ler ou gravar um programa iniciado pelo agente também
alcança. Medido por uma simulação adversarial em 2026-10-01 (registro em `docs/decisions/`), três
coisas continuam possíveis para um agente deliberado: um commit feito por uma rota que nenhum leitor
de comandos reconhece (um script em disco, o encanamento do próprio git) põe no histórico um arquivo
fora do escopo, e o fechamento então recusa a frente; o livro de evidências e o arquivo de estado
podem ser gravados por um programa que monta o caminho deles ao rodar — o escopo, os portões e a
fotografia são pegos depois pelos seus digests, o livro não; e uma afirmação de que o trabalho
terminou, dita fora do vocabulário do portão de parada, não é julgada. Cada um está escrito com o
seu motivo em [`docs/reference/roadmap.md`](docs/reference/roadmap.md) e exercitado em
`tests/attack.sh` como ataque DECLARADO, de modo que um limite que passa a ser recusado é reportado
como a cerca crescendo, e um buraco que ninguém declarou reprova o portão.

## Princípios

Os princípios embutidos são oito linhas numeradas, cada uma nomeando a falha que evita e o mecanismo
por trás. Leia em [`principles/PRINCIPLES.md`](principles/PRINCIPLES.md). Mantenha-os, ou aponte
`principles_file` para os seus.

## Desinstalação

```bash
claude plugin uninstall roadworthy@roadworthy
claude plugin marketplace remove roadworthy
```

## Licença

MIT.
