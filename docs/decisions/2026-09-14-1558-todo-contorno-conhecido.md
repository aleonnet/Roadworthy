status: accepted

# Todo contorno conhecido é recusado ou declarado — e a evidência de um projeto mora no projeto

## Contexto e problema

A 0.6.0 foi lida inteira (172 arquivos, 9.295 linhas) e depois medida ao vivo, no dia em que foi
publicada. O que a leitura e a medição encontraram, com o comando que as produziu:

1. **Uma cadeia fechava a frente `passed` por cima do próprio escopo.** O leitor de comandos do
   portão de entrada conhecia os verbos de escrita e não os de remoção, e o `mv` só olhava o destino
   (`hooks/rite-gate`). O fechamento pulava toda a verificação de digests e de arquivos fora do escopo
   quando o `plan.snapshot` não existia, e a impressão digital exclui o snapshot. Logo: abrir a frente,
   escrever fora do escopo pelo shell (limite declarado), `rm .roadworthy/plan.snapshot`, fechar — a
   frente fechava `passed`, sem nada STALE. `rm .roadworthy/state` limpava um `gaps_found`;
   `rm .roadworthy/overnight` encerrava a noite. Verificado arquivo a arquivo; reproduzido depois
   como ataque em `tests/attack.sh` ("removing the foundation") e como caso em
   `tests/hooks/rite-gate.sh`, vermelhos antes do conserto.
2. **A evidência de um projeto era procurada no diretório errado — medido às 13:33.** O `stop-gate`
   bloqueou um turno com os seis portões `MISSING`; um minuto depois `close.sh --check` no shell
   devolveu os seis `FRESH`. Comandos rodados no ato: `find "$HOME/.claude/plugins" -maxdepth 5
   \( -name 'evidence.jsonl' -o -name 'denials.jsonl' -o -name 'stop-latch' \) -print` mostrou
   `denials.jsonl` e `stop-latch/` em `~/.claude/plugins/data/roadworthy-roadworthy/` — e nenhum
   `evidence.jsonl` lá; o trinco desta sessão carregava a impressão digital exata da árvore
   (`46c99222931be64b`, de `tree-fingerprint.sh .`). A documentação oficial (plugins reference):
   `CLAUDE_PLUGIN_DATA` é por plugin, `~/.claude/plugins/data/{id}/`, exportada a todo hook. Um shell
   de pessoa não a define. O escritor do ledger de negações (`hooks/lib.sh`) resolvia por ela e o
   leitor (`hooks/principles`) não: as seis negações reais do dia estavam no diretório compartilhado
   e a linha "a fence has denied three times" nunca chegou a um prompt.
3. **Um registro aceito prometia um mecanismo que o código não tinha.**
   `2026-09-14-0239-four-accepted-claims-refuted.md` diz que a eleição do plano cai no transcript
   antes da data e avisa ao cair na data (aceites 16 e 17 do plano da 0.6.0, que existem no plano
   aprovado); `hooks/plan-review-gate` caía na data em silêncio.
4. **A configuração do dono era editável pelo agente.** `.roadworthy/protected` e
   `.roadworthy/overnight-rules` eram "configuração humana", isentas nas duas portas — e são o que
   `protect-paths` e a noite leem para vigiar o agente. Era o aceite 7 do plano aprovado da 0.6.0.
5. **`stop_hook_active` estava documentado** ("Claude Code overrides a Stop hook after it blocks
   eight times in a row without progress … Parse the `stop_hook_active` field"), e o comentário do
   `stop-gate` dizia que não.
6. **Dois lares do plano, três matchers de glob, quatro afirmações do CHANGELOG sem mecanismo** —
   detalhados em `CHANGELOG.md`, `[0.6.1]`.

## Opções consideradas

1. Declarar a cadeia do `rm` como limite ("o leitor é best effort") — recusada: o compensador do
   fechamento seria removível pelo mesmo agente que ele mede, e um limite que anula o compensador não
   é limite, é buraco.
2. Manter `CLAUDE_PLUGIN_DATA` na cadeia e ensinar o `stop-gate` a procurar nos dois lugares —
   recusada: dois leitores para um escritor é a forma do defeito; a regra tem de ser uma.
3. Recusar todo escopo sem snapshot — recusada: os moldes dos evals, as fixtures e os projetos
   anteriores à 0.6.0 escrevem o escopo à mão e não têm snapshot; a regra estrita poria um LLM menor
   diante de uma parede que ele não pode resolver.
4. Superar por registro novo a alegação dos aceites 16/17 em vez de implementá-la — recusada: o
   caso de campo de 2026-09-08 (revisão velha com nome reaproveitado) anda pelo mesmo caminho.

## Decisão

- **Remover é escrever.** `rm`, `unlink`, `rmdir`, `git rm` e a origem do `mv` são alvos do portão de
  entrada; nada sob `.roadworthy/` é removido à mão, o diretório incluído. `find -delete`, `xargs rm`
  e interpretadores seguem como limite declarado — com compensador nomeado.
- **Escopo do rito sem snapshot é adulteração.** A regra é pelo banner que `scope-write.sh` escreve na
  primeira linha do escopo: esse escopo exige `plan.snapshot`, e `close.sh` recusa sem ele, no
  fechamento e no `--check`. Escopo sem banner segue pelo caminho antigo.
- **A evidência de um projeto mora no projeto.** `rw_data_dir` em `hooks/lib.sh`: `ROADWORTHY_DATA`
  se definida, senão `<repositório>/.roadworthy`. Usado pelo escritor e pelo leitor do ledger de
  negações, pelo `stop-gate` (que o passa explicitamente ao `close.sh --check`), por `close.sh`,
  `plan-preflight.sh` e `refute.sh`. O pin do arquivo de princípios fica em `CLAUDE_PLUGIN_DATA`:
  global por construção. `stop_hook_active` honrado.
- **A configuração do dono é do dono.** As duas listas negadas ao agente nas duas portas; `docs.json`
  segue editável. Reverte o aceite 7 da 0.6.0.
- **O plano é eleito pelo texto, depois pelo transcript, depois pela data — anunciada.** E tem dois
  lares: `plans_dir` e o diretório `plans` do `docs.json`; o portão, o portão de entrada e a trava de
  escopo leem os dois.
- **Um matcher de glob** (`hooks/globmatch.py`); `run-hook.cmd` recusa sem bash, executado na CI;
  o Python embutido compilado e sem import morto; a suíte adversarial é a catraca: todo contorno
  conhecido em 2026-09-14 está nela como recusado ou declarado com o motivo (64 ataques).

## Consequências

- Boas: a frente não fecha por cima do próprio escopo; escritor e leitor da evidência concordam em
  qualquer ambiente; o LLM lê no prompt seguinte que uma cerca o negou três vezes; o plano escrito
  onde a norma da casa manda é encontrado; o que não é recusado está escrito, com o porquê, e a
  suíte adversarial reprova um contorno que passe sem declaração.
- Más: quem editava `protected` ou `overnight-rules` pelo agente passa a editá-los fora dele; quem
  guardava evidência em `CLAUDE_PLUGIN_DATA` aponta `ROADWORTHY_DATA` para lá; remover um arquivo
  qualquer do repositório pelo shell passa a exigir frente aberta, como escrever.
- Aposentado do roteiro: aposentadoria por bloco do escopo (funcionalidade sem projeto que a peça).

## Confirmação

- `bash tests/run.sh` → `RESULT: gate clean` com 30 casos; `bash tests/attack.sh` → `RESULT: every
  cheat refused, every pass declared`, 64 ataques (50 recusados, 14 declarados).
- Cada garantia acima refutada por `skills/refute/scripts/refute.sh` (defeito plantado, texto exato
  da falha, arquivo restaurado com SHA-256 conferido), registros em `.roadworthy/refutations.jsonl`;
  as linhas datadas estão nos cabeçalhos de `hooks/rite-gate`, `hooks/scope-lock`,
  `hooks/stop-gate`, `hooks/principles`, `hooks/plan-review-gate` e `skills/close/scripts/close.sh`.
- `bash tests/bench/bench.sh --model haiku` → `RESULT: the fences hold in a real session` (6 passos,
  2026-09-14): a prova de campo, em sessão real do harness, que as versões anteriores não tinham.
- A decisão está em vigor enquanto esses três comandos passam; deixa de estar no dia em que um
  ataque passa sem declaração ou um passo da bancada diverge.
