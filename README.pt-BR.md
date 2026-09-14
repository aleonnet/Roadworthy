# Roadworthy

[English](README.md) · **Português (Brasil)**

**Uma mudança, zero dano colateral.**

## TL;DR

Roadworthy é um plugin do Claude Code que transforma regras de qualidade em hooks. Um agente que
mexe em código faz uma coisa bonita e quebra outras dez; prosa não impede isso, um hook que nega a
edição impede.

- **Sem frente aberta, nada é escrito.** Até um plano declarar o escopo, toda edição e toda escrita
  pelo shell dentro do repositório é negada, nomeando o rito que abre uma frente.
- **Escopo declarado, escopo imposto.** Editar fora dos globs declarados é negado, e o fechamento
  recusa uma frente cujo diff saiu deles.
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
   (comandos dos portões) em blocos cercados, e `plan-preflight.sh` confere o plano mecanicamente
   antes que alguém o leia.
2. **Abrir.** `scope-write.sh <plano.md>` escreve `.roadworthy/scope`, `.roadworthy/gates` e a
   fotografia da aprovação num só ato. Daqui em diante as cercas estão ligadas.
3. **Trabalhar.** Edições fora do escopo são negadas; o próprio arquivo do plano continua editável.
4. **Fechar.** `/roadworthy:close` roda os portões depois do último commit, grava cada um com a
   impressão digital da árvore e libera o escopo. Só então o turno pode dizer "pronto".

## O que ele impõe (hooks)

| Hook | Evento | Garantia |
|---|---|---|
| `principles` | todo prompt | Injeta os seus princípios numerados e as regras numeradas do projeto, fixa o arquivo de princípios por digest e repete a terceira negação de uma cerca como uma linha no prompt seguinte. |
| `rite-gate` | Edit/Write **e Bash** | Sem `.roadworthy/scope` utilizável, nenhuma escrita e nenhuma remoção dentro do repositório. Os arquivos que só um script pode escrever são negados à mão, com ou sem frente; os dois arquivos do dono são do dono. |
| `scope-lock` | Edit/Write | Enquanto existe um escopo, uma edição fora dos globs dele é negada. Vigia as ferramentas de edição, não o shell; o fechamento pega o resto. |
| `protect-paths` | Edit/Write | Caminhos que casam com `protected_paths` (e com o `.roadworthy/protected` do projeto) nunca são editados. |
| `guard-commit` | Bash | `git commit` com flag proibida (padrão `--trailer`) ou sem nada em stage é negado. |
| `plan-review-gate` | ExitPlanMode | Um plano sai do modo de plano só quando o pré-voo está verde (padrão) ou uma banca fria diz `VERDICT: APPROVED` (`plan_gate`). |
| `stop-gate` | Stop | Uma afirmação de "pronto" é bloqueada enquanto `close.sh --check` não reporta todo portão declarado como FRESH. |
| `overnight-guard` | Bash | Enquanto `.roadworthy/overnight` existe, push, merge, tag, `gh pr merge` e as regras `deny:` do projeto são negados. |

<details>
<summary><strong>A letra miúda, hook por hook</strong> — o que cada um mede, e o caso de campo que o moldou</summary>

**`principles`.** Injeta os seus princípios numerados (o conjunto embutido ou o seu próprio arquivo)
mais as regras numeradas da memória do projeto atual, para que nunca percam saliência numa sessão
longa. Também **fixa o arquivo de princípios por digest**: o arquivo vive fora de todo repositório,
então nada impede que seja editado — o que isto faz é anunciar a mudança a cada prompt, nomeando o
digest e a data do último acordo, até você concordar com o texto novo. E quando a mesma cerca negou
**três vezes** na frente aberta, essa contagem volta como uma linha no prompt seguinte: um agente
não lembra, mas lê.

**`rite-gate`.** Enquanto o projeto não tem um `.roadworthy/scope` utilizável, toda edição, toda
escrita pelo shell e toda remoção pelo shell dentro do repositório é negada, nomeando o rito que
abre uma frente. Um arquivo de escopo **vazio** não conta: um `touch` bastava para satisfazer toda
verificação enquanto desligava a trava. Os arquivos que só um script pode escrever (escopo, portões,
fotografia, estado, livros-razão) são negados à mão com ou sem frente, **remover qualquer coisa sob
`.roadworthy/` é negado** (`rm`, `unlink`, `rmdir`, `git rm`, a origem do `mv`), e os dois arquivos
do dono — `.roadworthy/protected`, `.roadworthy/overnight-rules` — são do dono: o agente não os
edita nem remove. Uma frente registrada como `gaps_found` ou `needs_human` bloqueia a próxima. O
plano é isento nos seus dois lares (`plans_dir` e o diretório `plans` do `.roadworthy/docs.json`).
Medido neste repositório em 2026-09-13: 60 edições e 117 comandos de shell num dia, zero invocações
do rito, ninguém notou.

**`scope-lock`.** Enquanto `.roadworthy/scope` existe no projeto, qualquer edição fora dos globs
listados é negada. O próprio arquivo do plano (em qualquer dos seus dois lares) é isento: é o
artefato do rito. **A guarda vigia as ferramentas de edição, não o shell** — um `cat >` ou `sed -i`
rodado pelo Bash não é visto; veja [Limites declarados](docs/reference/roadmap.md). O que a
respalda é o fechamento: `close.sh` recusa uma frente cujo diff tocou um arquivo fora dos globs, e
recusa um escopo escrito pelo rito cujo `plan.snapshot` sumiu.

**`protect-paths`.** Caminhos que casam com `protected_paths` nunca são editados, decida o modelo o
que decidir.

**`guard-commit`.** `git commit` com uma flag proibida (padrão `--trailer`) ou sem nada em stage é
negado.

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
precisa nomear a mesma.

**`stop-gate`.** Um turno que diz que o trabalho terminou é bloqueado enquanto `close.sh --check`
não reporta todo portão declarado como FRESH, e o bloqueio mostra o estado de cada um. **Nunca
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
interno nega a ação, porque uma fronteira que falha aberta não é fronteira. O hook `principles`
falha aberto com um aviso visível, porque um erro na submissão do prompt jamais pode apagar o
prompt; o `stop-gate` também falha aberto, porque uma sessão que não consegue terminar é a falha
mais cara. Negações são decisões JSON estruturadas, nunca um exit 2 seco — exceto no `stop-gate`,
onde exit 2 é a forma que o evento Stop tem de bloquear um turno. **Toda negação é registrada** em
`.roadworthy/denials.jsonl` com a cerca, o motivo e a frente em que aconteceu, para que uma cerca
que dispara deixe rastro em vez de ser visível só num traço de eval que ninguém tem.

**Onde mora a evidência.** Livros-razão, trava, estado e registros de refutação vão para
`ROADWORTHY_DATA` quando a variável está definida, senão para `<repositório>/.roadworthy`. Não para
`CLAUDE_PLUGIN_DATA`: o Claude Code a define, para todo hook, como um diretório por plugin,
compartilhado por todo projeto da máquina, e o shell de uma pessoa não a define — quem escreve e
quem lê nunca se encontrariam (medido em 2026-09-14). A única coisa guardada lá é o pino do arquivo
de princípios, que vive fora de todo repositório.

**No Windows sem bash**, `hooks/run-hook.cmd` recusa em vez de deixar a chamada passar sem guarda:
uma cerca sai com 2 e o motivo no stderr, `principles` e `stop-gate` avisam com exit 1. Executado
num runner Windows na CI; não executado na máquina que o escreveu.

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

- **plan** — `[NEEDS CLARIFICATION]` em vez de suposições; `scope-write.sh` abre a frente a partir
  dos blocos cercados do plano; `plan-preflight.sh` confere citações por conteúdo, caminhos do
  escopo, numeração do aceite, correções declaradas e leitura de arquivo inteiro provada pela
  transcrição.
- **refute** — `skills/refute/scripts/refute.sh` faz isso mecanicamente e escreve o registro. Uma
  refutação roda a sua verificação duas vezes, então doze delas custam doze rodadas da suíte: uma
  vez por garantia, não a suíte inteira a cada mudança.
- **close** — `close.sh` roda os portões de `.roadworthy/gates` e diz FRESH/STALE/MISSING depois
  com `--check`; `close-front.sh` move uma frente fechada para o histórico com os links reescritos.
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
| `rite_gate` | `true` | Negar edições e escritas pelo shell enquanto nenhuma frente está aberta, e negar escritas nos arquivos que só um script pode escrever. |
| `scope_lock` | `true` | Honrar `.roadworthy/scope`. |
| `forbidden_commit_flags` | `--trailer` | Flags separadas por vírgula negadas em comandos de commit. |
| `block_empty_commits` | `true` | Negar `git commit` sem nada em stage. |
| `plan_gate` | `preflight` | O que guarda um plano: `preflight` confere mecanicamente; `review` é o veredito adversarial anterior à 0.6.0; `both` são os dois. |
| `plan_review_required` | `true` | Exigir a banca antes do ExitPlanMode. Ela se liga ao plano por nome, nunca por hash: o que o usuário aprovou é o que conta. |
| `max_review_rounds` | `2` | Rodadas de banca fria que um plano pode ter antes que só a decisão escrita do usuário (uma linha `owner:`) o destrave. A rodada 3 não existe. |
| `review_suffix` | `.review.md` | Sufixo do arquivo de banca ao lado do plano. |
| `plans_dir` | `~/.claude/plans` | Onde o Claude Code escreve os planos do modo de plano. Compartilhado por todo projeto, então um plano declara `project:` no cabeçalho. O segundo lar é o diretório `plans` do `.roadworthy/docs.json`. |

**Uma opção alterada não chega a uma sessão que já está aberta.** O Claude Code lê as opções ao
carregar o plugin, então depois de mudar uma rode **`/reload-plugins`** ou abra uma sessão nova.
Medido em 2026-09-13: a opção estava certa no disco, o hook a honrou quando a variável chegou até
ele, e a sessão aberta seguia negando com o valor antigo.

## Testes

```bash
bash tests/run.sh              # o portão inteiro: 30 casos, ~3 min
bash tests/hooks/scope-lock.sh # uma cerca, sozinha, em segundos
bash tests/attack.sh           # a suíte de trapaças: 64 ataques, 50 recusados, 14 declarados
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

**A suíte dispara eventos sintéticos; a bancada dispara uma sessão.** `tests/bench/bench.sh` carrega
os hooks da árvore de trabalho em `claude -p --plugin-dir` sobre um repositório de brinquedo, um ato
exato por prompt, e lê os próprios `permission_denials` do harness e o disco: sem frente → edição
negada; o rito abre a frente; edição fora do escopo negada; `rm .roadworthy/plan.snapshot` negado;
afirmação de "pronto" sobre portões FRESH não bloqueada; negações no livro-razão do projeto. Toda
versão antes da 0.6.1 saiu "provada pela suíte, não provada em campo"; isto é o campo.

| Onde | O quê |
|---|---|
| `tests/run.sh` | o executor: lê `tests/cases.txt`, roda cada caso (quatro por vez), incorpora a suíte de ataques |
| `tests/cases.txt` | **o manifesto, e a cerca.** Um executor que varre um diretório perde um caso no dia em que o arquivo é apagado e não diz nada; este recusa rodar quando a lista e o diretório discordam, em qualquer direção |
| `tests/lib.sh` | `ok`/`fail`, `run_hook`, `denied`, `golden`, a raiz temporária e `rw_end` |
| `tests/hooks/`, `tests/scripts/`, `tests/meta/` | um caso por cerca, por script e para a higiene da própria suíte |
| `tests/fixtures/` | os repositórios de brinquedo, árvores de documentação, planos e transcrições, construídos por nome |
| `tests/goldens/` | os envelopes de negação e de contexto, comparados chave a chave |
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

Alguns buracos são decididos, não pendentes: a trava de escopo vigia as ferramentas de edição e não
o shell; o leitor de comandos de shell é melhor esforço e diz isso; evidência escrita na máquina
atacada pode ser forjada; o portão de parada julga uma enumeração nomeada de palavras de "pronto".
Cada um está escrito com o seu motivo em [`docs/reference/roadmap.md`](docs/reference/roadmap.md) e
exercitado em `tests/attack.sh` como ataque DECLARADO, de modo que um limite que passa a ser
recusado é reportado como a cerca crescendo, e um buraco que ninguém declarou reprova o portão.

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
