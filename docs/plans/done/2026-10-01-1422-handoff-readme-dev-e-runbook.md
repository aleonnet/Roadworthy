status: superado por 2026-10-01-1807-handoff-0-7-1.md

# Handoff — guia do dev e runbook — 2026-10-01 14:22

> Leia isto primeiro. Supera `2026-10-01-1150-handoff-0-7-0.md`. Todo número vem com o comando
> rodado no ato, nesta máquina, em 2026-10-01. Este arquivo é escrito e commitado ANTES do fecho;
> a prova do fecho fica no livro de evidências (`.roadworthy/evidence.jsonl`), e o que vem depois
> dele (push, CI) está no fim, marcado como não medido aqui.

## Estado (medido no ato, antes do commit)

- Ramo `main`, base da frente `2120be4`. `git rev-list --left-right --count origin/main...main`
  → `0 0` antes do commit desta frente.
- Versão do plugin: 0.7.0, sem mudança. Esta frente é só documentação e fica em `[Unreleased]`.
- Frente aberta de `2026-10-01-1348-readme-dev-e-runbook.md`, reaberta duas vezes pelo mesmo
  plano (base mantida): dez portões declarados.

## O que esta frente fez

Um dev humano passa a ter por onde começar:

- `README_DEV.md` (242 linhas) e o gêmeo `README_DEV.pt-BR.md` (250 linhas): a ideia do plugin
  numa tela, o mapa do código (onde mora o que faz X), os invariantes, as preocupações que
  atravessam tudo, o que tocar junto ao mudar cada coisa, e onde ler depois.
- `docs/guides/runbook.md` (260 linhas, em inglês): catorze situações reais, cada uma com quando
  usar, o que rodar, o que esperar e o que fazer se não for isso.
  (`wc -l README_DEV.md README_DEV.pt-BR.md docs/guides/runbook.md`, depois das correções da
  leitura fria; os tetos do plano são 250, 250 e 300.)
- `README.md`, `README.pt-BR.md` e `docs/README.md` apontam para eles; o CHANGELOG registra.
- Dois portões novos: todo gancho registrado, auxiliar e script de skill tem de estar nomeado
  nos dois guias (`dev-map`), e os dois guias têm de concordar em seções e se apontar
  (`readme-dev-parity`).

A forma veio de fontes conferidas no texto da página (`curl` + `grep`), citadas literalmente no
plano: matklad (ARCHITECTURE.md), Diátaxis, o guia de documentação do Google, o livro de SRE do
Google, a documentação do GitHub, a do Claude Code e Write the Docs.

## O que foi rodado do runbook (aceite 5 do plano)

Repositórios de brinquedo na pasta temporária da sessão, e este repositório onde indicado.

| Entrada | Comando | Saída observada |
|---|---|---|
| Árvore de trabalho numa sessão real | `claude plugin validate . --strict` | `✔ Validation passed` |
| | `claude --plugin-dir . plugin list` | `roadworthy@inline`, `Status: ✔ loaded`, ao lado do instalado `roadworthy@roadworthy` |
| | `claude --plugin-dir .` (sessão interativa) | NÃO rodado; a bancada carrega a árvore pela mesma opção (`claude -p --plugin-dir`) e passou |
| | `claude plugin disable` / `enable` | NÃO rodados (mexem na instalação do dono); os subcomandos existem em `claude plugin --help` |
| Testes | `bash tests/hooks/scope-lock.sh` | linhas `[OK]`, saída 0 |
| | `RW_SIM_ONLY=live-01 bash tests/meta/rite-liveness.sh` | `[OK] live-01-work-inside-an-open-front: held (13 steps)` |
| | `python3 tests/sim/rite-sim.py <cenário>` | uma linha por passo, `RESULT: held` |
| | `bash tests/bench/bench.sh` | `10 step(s), 0 failure(s)` · `RESULT: the fences hold in a real session` |
| | `bash tests/run.sh` e `bash tests/attack.sh` | rodam no fecho (portões 1 e 2); `RW_JOBS=1` não foi rodado |
| Trabalhar pelo rito | `plan-preflight.sh <plano> --transcript <transcrição>` | `plan-preflight: green` (três vezes, neste repositório) |
| | `scope-write.sh <plano>` | `scope-write: front open from …`; reaberta: `front reopened … (kept from when the front opened)` |
| | `git status --short` depois de abrir | ` M .roadworthy/gates`: o arquivo dos portões é reescrito e vai no commit da frente |
| | `scope-write.sh <plano> --owner` | NÃO digitado: é ato do dono; a bancada o exercita |
| O fecho recusa | `close.sh --check` | `MISSING`, depois `FRESH` e `FRESH-RED`, depois `STALE`, nos três momentos |
| | `close.sh` com árvore suja | `close: the tree is dirty; commit first` |
| | `close.sh` com portão vermelho | `FAIL … (exit 1)` · `close: gaps_found — 1 gate(s) red; scope kept` |
| | `close.sh` com arquivo fora do escopo commitado | `close: the front touched 1 file(s) outside its declared scope` |
| | `close.sh` sem frente aberta | `close: no front is open here — the last one (p.md) already ended as 'passed'` |
| | `close.sh --abandon "<motivo>"` | `close: front abandoned — … State gaps_found; scope released.` |
| | `close.sh` verde | `close: passed — evidence in …; scope released` |
| "not the front that was approved" | evento de edição entregue à mão ao `rite-gate` | negação com `is not the front that was approved: no approval is on record` |
| Turno bloqueado no fim | evento Stop entregue à mão ao `stop-gate` | o texto do bloqueio com os portões `STALE`, saída 2; a mesma árvore de novo: saída 0 |
| Verificação de pessoa | `close.sh --needs-human "<item>"` e `close.sh --human` | `close: needs_human — …`; a lista com o id; `--state` diz `needs_human` |
| | linha `rw-human: all approved` num prompt | entregue à mão ao `principles` num brinquedo: `THE OWNER ANSWERED A HUMAN VERIFICATION IN THIS PROMPT, and it is recorded`. NÃO feito num prompt real do dono |
| | o agente digitando a resposta | negado: `a human verification is answered by the person, not by the agent` |
| Gancho que nega ou erra | os três comandos da entrada | negação em JSON; `W … outside/b.py` e `R … build`; o texto de estado do início de sessão |
| Livros de registro | os dois comandos de uma linha | uma linha por negação e por evidência, neste repositório |
| Provar que uma verificação falha | `refute.sh --file … --sed … --expect … -- <verificação>` | `refute: OK — red with the defect (…), green on the clean file, … restored (hash verified)` |
| Publicar uma versão | `gh run list --limit 3` · `claude plugin details roadworthy@roadworthy` | `completed success`; `Roadworthy (roadworthy) 0.7.0`. `claude plugin update` NÃO rodado (não há versão nova) |
| CI vermelha | `gh run view <id> --log-failed` | rodado sobre uma execução verde: não imprime nada |
| Desligar uma cerca | `/plugin`, Configure, `/reload-plugins` | NÃO rodado (tela interativa do dono); vem do `README.md` |
| Marcador da madrugada | `overnight-start.sh`, `overnight-entry.sh`, `overnight-close.sh --run` | `on since …`; `git push` negado com `overnight mode is on`; `overnight-close: off at … — hand-off …` |
| | `rm .roadworthy/overnight` | NÃO rodado: é ato do dono, fora do agente |

## A leitura fria do diff (2026-10-01)

Um revisor que viu só o diff, os critérios e o código reprovou a primeira rodada: nove bloqueios
e uma afirmação não verificada, todos de redação, nenhum pedindo decisão do dono. Conferidos um
a um no código, todos procediam, e foram corrigidos nos dois guias, no runbook e no plano:

1. "Uma gramática para cada coisa, e todo chamador lê de lá" era falso: `overnight-guard` e
   partes do `guard-commit` casam o texto cru do comando, e `plan-preflight.sh` lê sozinho as
   seções do plano. O invariante passou a dizer isso, e que não se acrescenta cópia.
2. O runbook dizia que a CI do Windows fica vermelha se um gancho novo faltar na lista do
   lançador; o job chama quatro ganchos pelo nome e não vê um novo.
3. O runbook mandava passar a resposta de um gancho por `python3 -m json.tool`, que dá erro
   quando a resposta é vazia — justamente o caso "a chamada passa". Faltava também a terceira
   resposta possível, a que só traz contexto.
4. `plan-review-gate` descrito como falhando fechado antes e depois; a metade de depois falha
   aberta.
5. "Os scripts são os únicos que escrevem o estado do rito" era falso para os livros: ganchos
   acrescentam aprovações, vereditos, negações e a trava do fim de turno.
6. "Qualquer código de saída diferente de 2" → código não zero e diferente de 2.
7. `scope-lock` não é o menor gancho (`wc -l`: 87 linhas; `overnight-guard` 56, `protect-paths` 58).
8. A lista dos lugares que soletram os arquivos de estado local estava incompleta em três.
9. O plano dizia dezesseis scripts de skill; são catorze.
10. Não verificado, e agora dito como é: a aprovação gravada "quando a pessoa aprova" — a única
    evidência de sessão real é o caminho de reserva (o primeiro achado abaixo).

Depois dessa rodada varri eu mesmo a classe nos três documentos (toda frase com "todo", "só",
"nunca", "nenhum", conferida por comando) e corrigi mais cinco que o revisor não tinha citado:
os hooks não julgam "toda chamada de ferramenta", só as que mudam alguma coisa; o portão de
entrada "nega só o que nomeia" vale para arquivo comum; "um processo morto responde com
negação" era largo demais; "nunca contra arquivos relidos" virou a regra dos digests; e o caso
de privacidade não confere bytecode em geral.

**A segunda rodada, o teto, também reprovou.** Confirmou resolvidos os nove da primeira e achou
sete frases novas da mesma classe. Não houve terceira rodada: cada uma foi medida por comando
meu, corrigida nos dois guias e no runbook, e é essa medição — não um terceiro leitor — o que
sustenta o texto que vai no commit:

1. "O `hygiene.sh` compila cada bloco" era falso: 27 aberturas de Python embutido, 22 achadas
   pelo padrão dele (achado 4, abaixo). O guia diz agora o que o padrão acha e o que não acha.
2. "Só scripts e hooks escrevem sob `.roadworthy/`" e "os cinco arquivos do dono, do dono": o
   dono escreve os dele à mão, e `docs-init.sh` cria o `docs.json`.
3. "Nunca o diretório da sessão": um arquivo fora de qualquer repositório cai no da sessão.
4. "O cabeçalho de cada arquivo diz como foi refutado": vale para os dez hooks; `hooks/lib.sh`
   tem zero linhas `Refuted`.
5. "Sob `set -u` o trap de EXIT vê status 0": só com `set -e` junto, que é como a suíte roda
   (`/bin/bash` 3.2.57: `set -u` sozinho → o trap vê 1; `set -euo pipefail` → vê 0).
6. "O motivo é de dois tipos": `hooks/frontcheck.py` devolve cinco textos, de três tipos.
7. A lista dos lugares que soletram o estado local ainda deixava um de fora
   (`tests/hooks/rite-gate.sh`); o guia deixou de enumerar e passou a dar o comando que os lista.

Nenhuma das duas leituras deixou registro `review` no livro de evidências (achado 5).

## Achados no código durante a escrita (nenhum corrigido aqui: estava fora do escopo)

1. **A aprovação pela tela é gravada pelo caminho de reserva, não pelo gancho do pós-aprovação.**
   Três aprovações de plano nesta sessão; os três registros `approval` do livro de evidências
   trazem `source: transcript` e a hora em que o `scope-write.sh` foi julgado, não a hora da
   aprovação. O gancho registrado para depois do `ExitPlanMode` não deixou registro nenhum. O
   efeito para quem usa é nulo — a frente abriu do plano aprovado nas três vezes —, mas o caminho
   principal não foi visto funcionando numa sessão real. Causa não diagnosticada.
2. **Uma cerca que recebe JSON inválido nega por acidente.** Entregue `not json` ao `scope-lock`:
   a resposta é uma negação (correto), mas o motivo diz `internal error at line 95` e o stderr
   traz `{hookSpecificOutput:: command not found`, em vez de `invalid JSON on stdin`. O texto da
   negação de dentro da substituição de comando é capturado e depois executado como comando.
3. **O veredito de um revisor frio real não foi gravado.** Duas leituras frias rodaram nesta
   sessão, as duas terminando com a linha `VERDICT: REJECTED`, e o livro de evidências não tem
   nenhum registro `review` (contagem por tipo, no ato: 132 de portão, 2 de fecho, 3 de
   aprovação). A bancada mede esse registro numa sessão sem interface e passou hoje; numa sessão
   interativa como esta, não apareceu. Consequência, lida no código e não testada: num projeto
   que exija `diff_review: required` ou banca de plano, o fecho e a submissão ficariam sem o
   veredito de que precisam. Causa não diagnosticada; a hipótese do próprio revisor é que o
   relatório chega por chamada de ferramenta e o campo que o gancho lê vem sem a linha.
4. **A higiene da suíte não vê cinco blocos de Python embutido.** O padrão de
   `tests/meta/hygiene.sh` só acha uma abertura de heredoc cuja etiqueta termina a linha; ficam
   de fora, sem compilar e sem a checagem de import morto, `hooks/lib.sh:189`,
   `hooks/plan-review-gate:101`, `hooks/review-record:55`, `skills/close/scripts/close.sh:392` e
   `skills/refute/scripts/refute.sh:86` (27 aberturas, 22 achadas, medido com o mesmo padrão).
   O `README.md` e o `README.pt-BR.md` dizem "todo bloco de Python embutido é compilado": é a
   frase que fica desencontrada do guia até o padrão ser consertado. Não mexi nela: o conserto
   certo é no padrão, que é código.
5. **Dois itens da bancada do dono, da lista do handoff anterior, foram vistos nesta sessão:** a
   linha de estado no começo da sessão (apareceu) e a frente abrindo de um plano aprovado na
   tela (abriu, pelo caminho do item 1). A forma de relatar combinada no plano também voltou a
   cada prompt. Falta o terceiro: responder uma verificação com `rw-human:` num prompt real.

## Onde o estado real mora

- `README_DEV.md`, `README_DEV.pt-BR.md`, `docs/guides/runbook.md` — a entrega.
- `docs/plans/done/2026-10-01-1348-readme-dev-e-runbook.md` — o plano, com as fontes em citação
  literal, as duas emendas e a seção Refutação.
- `.roadworthy/gates` — os dez portões do fecho.
- `CHANGELOG.md`, `[Unreleased]`.

## Placar — o que esta frente errou no caminho

| classe | o que foi |
|---|---|
| Afirmação universal escrita sem o `grep` que a sustenta | "todo chamador lê de lá", "os únicos que escrevem", "o menor", "qualquer código de saída", "ou o job fica vermelho": cinco dos nove bloqueios da primeira leitura fria; a minha varredura da classe pegou mais cinco e ainda deixou sete para a segunda ("cada bloco", "nunca o diretório da sessão", "cada arquivo", "de dois tipos"). Cada um se media com um comando de uma linha |
| Frase copiada de um documento da casa sem medir de novo | "compila cada bloco" e "sob `set -u` o trap vê 0" vieram do `README.md`; as duas estavam largas demais na origem |
| Comando do runbook provado só no caso que dá resposta | `python3 -m json.tool` foi rodado sobre uma negação e nunca sobre a resposta vazia |
| Nome de arquivo dentro de expressão regular sem escapar o ponto | o portão `dev-map` ficou verde com `shellread.py` trocado por `shellread-py`; a contraprova declarada no plano reprovou o portão, e ele passou a comparar por texto fixo |
| Comando da varredura que depende do shell de quem roda | usei `ls` em dois comandos; neste shell `ls` é outro programa e os dois falharam; troquei por `printf` e `find` antes de escrever o plano |
| Plano emendado duas vezes depois de aprovado | uma pelo dono (o gêmeo em português), uma por defeito meu (o portão acima); cada uma custou uma aprovação a mais |
| Passo do rito que eu não tinha lido como obrigação | a primeira tentativa de fecho no brinquedo parou em árvore suja: `.roadworthy/gates` é reescrito na abertura e tem de ser commitado; virou frase do runbook |
| Aceite escrito mais largo do que o possível | "todo comando do runbook é rodado" não vale para os atos reservados a uma pessoa nem para a tela do `/plugin`; estão marcados NÃO na tabela acima |

## Limites abertos

- O runbook existe só em inglês; o gêmeo em português não foi pedido.
- Não há `CONTRIBUTING.md`: o GitHub só mostra sozinho o arquivo com esse nome.
- Os três limites declarados da 0.7.0 seguem como estavam; o redesenho que os fecha continua sem
  plano aprovado.

## Próximo passo concreto

1. `bash skills/close/scripts/close.sh` sobre o commit que leva este arquivo → `close: passed`,
   dez portões.
2. `git push` (toque do dono na YubiKey) → `git rev-list --left-right --count origin/main...main`
   em `0 0` e `gh run list --limit 3` verde nos três jobs.
3. Decisões do dono que ficaram registradas: o `CONTRIBUTING.md`; o runbook em português; os
   quatro achados de código acima, que pedem frente própria se forem para conserto.

## Prompt para colar

```
Roadworthy: leia docs/plans/2026-10-01-1422-handoff-readme-dev-e-runbook.md ANTES de agir. Confira
no ato: git status, git rev-list --left-right --count origin/main...main, close.sh --state,
close.sh --check, gh run list --limit 3. Aberto: os quatro achados de código do handoff (a
aprovação gravada pelo caminho de reserva; a cerca que nega JSON inválido por acidente; o veredito
do revisor frio que não foi gravado numa sessão interativa; os cinco blocos de Python que a
higiene da suíte não vê), o rw-human num prompt real, e a frente do redesenho, ainda sem plano.
```

Se o fecho, o push ou a CI tiverem falhado, cole o erro literal junto.

## Painel de fechamento — 2026-10-01 14:22 (antes do `close.sh`)

1. **O que mudou para o dono:** existe um guia para quem mantém o plugin, nas duas línguas, e um
   runbook; um gancho ou script novo que não entrar no guia reprova o fecho.
2. **Entregue, por caminho:** `README_DEV.md`, `README_DEV.pt-BR.md`, `docs/guides/runbook.md`;
   uma passagem em `README.md`, `README.pt-BR.md` e `docs/README.md`; `CHANGELOG.md`;
   `.roadworthy/gates`; o plano e o handoff anterior em `docs/plans/done/` com linha no índice;
   este handoff.
3. **Próximo a entregar e o que consome deste:** o fecho consome o commit; o push consome o
   fecho; a CI consome `tests/run.sh`.
4. **Prova, comando rodado no ato → saída:** os cinco portões de documento, rodados pelo bash
   como o fecho os roda → `pointers-check: OK`, e saída 0 nos de paridade e de mapa;
   `docs-check: OK`; `lychee --offline` sobre os quatro READMEs e `docs/` → `0 Errors`; seis
   registros de refutação dos dois portões novos, todos vermelhos com o defeito, verdes no
   arquivo limpo e restaurados por hash; `bash tests/bench/bench.sh` → `10 step(s), 0
   failure(s)`. A suíte inteira e os ataques rodam no fecho, e é essa rodada que vale.
5. **Dentro da tolerância?** Não: o plano foi aprovado três vezes em vez de uma; as duas rodadas
   da leitura fria reprovaram (nove bloqueios, depois sete), e a resposta à segunda foi
   verificada por comando, não por um terceiro leitor; o aceite 5 tem os itens marcados NÃO.
6. **Números antes → depois:** portões declarados 8 → 10; documentos para quem mantém 0 → 3,
   somando 752 linhas (`wc -l` dos três, depois das correções: 242, 250 e 260, nos tetos de
   250, 250 e 300).
7. **Acervo tocado:** criados: os três documentos e este handoff; movidos para `done/`: o plano
   e o handoff das 11:50; apagado: nada.
8. **Limite ainda aberto:** os quatro achados de código; o `rw-human:` num prompt real; a CI, que
   só se mede depois do push.
9. **Decisão do dono:** o toque na YubiKey no push; se os quatro achados viram frente; o
   `CONTRIBUTING.md`; o runbook em português.
