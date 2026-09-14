status: accepted

# Handoff — README em duas línguas, o fecho da 0.6.1 — 2026-09-14 18:53

> Leia isto primeiro. Supera `2026-09-14-1750-handoff-0-6-1.md`, cuja seção "Ainda aberto" ficou no
> passado: os quatro itens foram feitos pelo dono e estão medidos abaixo. Todo número aqui vem com o
> comando rodado no ato, nesta sessão.

## Estado (medido no ato)

| Repositório | Ramo | HEAD ao abrir esta frente | Versão | Cópia instalada |
|---|---|---|---|---|
| `roadworthy` | `main`, igual a `origin/main` | `531f8f3` | 0.6.1 nos dois manifests | **0.6.1** (`claude plugin details roadworthy@roadworthy`) |

| o que o handoff anterior deixou aberto | comando | resultado |
|---|---|---|
| push da 0.6.1 | `git rev-list --left-right --count origin/main...main` | `0 0`: nada à frente, nada atrás |
| CI no GitHub | `gh run view 34898131666 --json jobs` | success: `tests/run.sh` (macos, ubuntu), `run-hook.cmd without bash (windows)`; `evals-bash` pulado (sem o segredo, como declarado) |
| `plugin update` + `/reload-plugins` | `claude plugin details roadworthy@roadworthy` | 0.6.1; `hooks/` e `skills/` idênticos à árvore (`diff -rq`) |
| links do Docker | `find ~/.docker -type l \| wc -l` | 37, igual ao `docker-links-targets.txt` do script de desfazer |
| portões | `close.sh --check` | seis FRESH em `531f8f3` |

## O que esta frente fez

Pedido do dono: auditar se toda a documentação está atualizada; revisar o README; gerar a versão
em português do Brasil chaveável para o inglês; TL;DR e divulgação progressiva; commit e push.

Auditoria (arquivos lidos inteiros): `README.md`, `CHANGELOG.md`, `docs/README.md`,
`docs/reference/roadmap.md`, os cinco `SKILL.md`, `agents/cold-reviewer.md`, `evals/README.md`,
`evals-round2/README.md`, `hooks/hooks.json`, os dois manifests, `principles/PRINCIPLES.md` e o
handoff anterior. Desatualizado, medido:

| onde | dizia | medido | comando |
|---|---|---|---|
| `README.md` | "the four guards fail closed" | seis cercas com `RW_ON_CRASH=deny` | `grep -n 'RW_ON_CRASH' hooks/*` |
| `README.md` | "about 468 tokens always on, 220 to 530 per skill" | ~772 sempre ligados; 310 a 3.700 por invocação | `claude plugin details roadworthy@roadworthy` |
| `hooks/hooks.json` | "exit 2 is never used" | o `stop-gate` sai com 2 (contrato do evento Stop) | `grep -n 'exit 2 is never used' hooks/hooks.json` |
| handoff `1750` | quatro itens "ainda abertos" | os quatro feitos | tabela acima |

O resto (CHANGELOG, roteiro, skills, evals, mapa, princípios) está coerente com a árvore.

Entregue:
- `README.md` — divulgação progressiva: troca de idioma sob o título, TL;DR de quatro
  garantias, instalação, a primeira frente em quatro passos, uma linha por hook e por skill, e a
  letra miúda dobrada em quatro blocos `<details>`. As duas frases falsas corrigidas; nada medido
  foi apagado, migrou para as dobras.
- `README.pt-BR.md` — a mesma página em português do Brasil, seção por seção e dobra por dobra;
  as duas se apontam sob o título (o chaveamento que o GitHub renderiza: README não roda script).
- Portão novo em `.roadworthy/gates`: as duas páginas têm o mesmo número de seções `## ` e de
  `<details>` e apontam uma para a outra. Refutado ao nascer, duas vezes (seção removida do PT-BR;
  link cruzado trocado no EN): vermelho com `readme-parity: README.md and README.pt-BR.md
  disagree`, verde no arquivo limpo, hash conferido; registros em `.roadworthy/refutations.jsonl`.
- `hooks/hooks.json` — só a `description`.
- `CHANGELOG.md` — `[Unreleased]`, "Changed".
- O plano `2026-09-14-1841-readme-em-duas-linguas.md`, movido para `docs/plans/done/` com linha no índice.

## Onde o estado real mora

- `CHANGELOG.md`, `[Unreleased]` — o que mudou e a medição por trás.
- `docs/plans/done/2026-09-14-1841-readme-em-duas-linguas.md` — o plano, com aceite, correções
  declaradas e o portão de paridade.
- `docs/reference/roadmap.md` — feito, pendente, aposentado, limites declarados (sem mudança nesta
  frente).
- `.roadworthy/gates` — sete portões, o sétimo é a paridade dos READMEs.

## Placar — o que esta frente errou no caminho

| classe | o que foi | defeito |
|---|---|---|
| Portão que falha em silêncio | o portão de paridade nasceu como um `test` mudo; `refute.sh` exige o texto da falha, e um portão sem texto não diagnostica nada; ganhou a frase `readme-parity: …` e a frente foi reaberta pelo `scope-write.sh` | plano, Verificação |
| Cláusula medida caiu na reescrita (leitor frio, rodada 1, bloqueio) | ao encurtar a nota do `/reload-plugins`, a observação do meio da medição de 2026-09-13 ("o hook a honrou quando a variável chegou") sumiu nos dois idiomas enquanto o CHANGELOG dizia "nada medido foi apagado"; restaurada; a classe é conferir o diff contra `git show HEAD:README.md` frase a frase, que eu não fiz | `README.md`, `README.pt-BR.md` |
| Mais duas frases caídas, achadas pela minha varredura depois do leitor | comparei cada frase de `git show HEAD:README.md` com o novo, espaço normalizado: faltavam "a tabela de bancada que o usuário preenche" (overnight) e "o que o usuário aprovou é o que conta" (`plan_review_required`); restauradas nos dois idiomas; o resto das 30 ausências era frase reescrita com o mesmo conteúdo ou artefato da divisão por tabela | `README.md`, `README.pt-BR.md` |
| Garantia condicional promovida a manchete (leitor frio, não verificado) | o TL;DR dizia "sem bump de versão à noite"; `overnight-guard` nega push, merge, tag e `gh pr merge`, e versão só congela por `freeze:` do projeto; o TL;DR passou a dizer isso | `README.md`, `README.pt-BR.md` |
| Posição afirmada sem medir (leitor frio, bloqueio menor) | o CHANGELOG dizia "na primeira linha"; a troca de idioma está sob o título (linha 3); corrigido | `CHANGELOG.md` |
| Comando lido como link | o portão de paridade grepava colchete-fecha seguido de `(README.md)`, e `docs-check.sh` leu esse literal dentro do plano (e depois deste placar, na primeira redação) como um link relativo quebrado; o portão passou a grepar `(README.md)`, a frente foi reaberta e refutada de novo | `docs-check.sh` |
| Caminho absoluto de home num plano guardado no repositório | o molde do plano pede `project:` absoluto; ao mover o plano para `docs/plans/done/`, a varredura de privacidade da suíte ficou vermelha (`/Users/…`); o portão expande `~` (`hooks/plan-review-gate`, função `same`), então o plano declara `project: ~/Development/roadworthy`. O molde em `skills/plan/templates/plan.md` ainda diz "absolute path": fora do escopo desta frente, anotado abaixo | `tests/meta/privacy.sh` |
| Pré-voo lendo a base errada | sem `base:` no plano, o pré-voo pegou o `plan.snapshot` da frente anterior (`50a81a6`) e acusou o handoff `1750` como inexistente; a base desta frente é a árvore, passada com `--base HEAD` | `plan-preflight.sh` |

## Limite ainda aberto

- `skills/plan/templates/plan.md` pede `project:` como caminho absoluto; um plano guardado dentro
  do repositório e commitado reprova a varredura de privacidade da suíte com esse caminho. O portão
  aceita `~` (medido nesta frente). Corrigir o molde e a skill é uma frente própria, em `skills/`.

## Próximo passo concreto

1. `git push` (ordenado pelo dono neste prompt) → `gh run list --limit 3` deve mostrar o run verde.
2. O primeiro uso real da 0.6.1 noutro projeto, como o roteiro e o handoff anterior já diziam.

## Prompt para colar

```
Roadworthy: leia docs/plans/2026-09-14-1853-handoff-readme-em-duas-linguas.md ANTES de agir, depois
[Unreleased] do CHANGELOG e o roteiro. Confira no ato: git status, close.sh --check, gh run list --limit 3.
Aberto: nada nesta frente; próximo é o primeiro uso real da 0.6.1 noutro projeto.
```

## Painel de fechamento — 2026-09-14 19:15 (hora do `close.sh`)

1. **O que mudou para o dono:** o README abre pelo essencial em inglês ou em português do Brasil,
   com a letra miúda dobrada e um portão que impede as duas páginas de divergirem; as três frases
   que a árvore não sustentava estão corrigidas e o handoff da 0.6.1 está superado por este.
2. **Entregue, por caminho:** `README.md`, `README.pt-BR.md`, `hooks/hooks.json` (só a
   `description`), `CHANGELOG.md` (`[Unreleased]`), `.roadworthy/gates` (sétimo portão, paridade),
   `docs/plans/done/2026-09-14-1841-readme-em-duas-linguas.md` e sua linha em
   `docs/plans/done/README.md`, `docs/plans/2026-09-14-1750-handoff-0-6-1.md` (status), este handoff.
3. **Próximo a entregar e o que consome deste:** o push (ordenado pelo dono) consome os commits
   `78a653a`, `67e3467` e o deste painel; a CI consome `tests/run.sh`; nenhum código novo.
4. **Prova, comando rodado no ato → saída:** `bash skills/close/scripts/close.sh` → `close: passed`,
   7 portões OK em `67e3467` (árvore `b291471eab154795`); `bash tests/run.sh` → `30 case(s) run`,
   `RESULT: gate clean`; `bash tests/attack.sh` → `RESULT: every cheat refused, every pass declared`
   (50 recusados, 14 declarados); `docs-check: OK`; `pointers-check: OK` nos dois READMEs; o portão
   de paridade sai 0; `claude plugin validate . --strict` → `Validation passed`;
   `plan-preflight.sh --closing` → verde (4 correções declaradas feitas). **Contraprovas que
   refutam:** 4 registros em `.roadworthy/refutations.jsonl` (seção `## Licença` apagada do PT-BR;
   link cruzado trocado no EN; as duas repetidas após o portão ganhar texto de falha), cada um
   vermelho com `readme-parity: README.md and README.pt-BR.md disagree`, verde no arquivo limpo,
   hash conferido. Leitor frio sobre o diff: rodada 1 REJECTED com 2 bloqueios e 1 não verificado,
   todos mecânicos e aplicados sem rodada nova (placar acima); a minha varredura frase a frase
   contra `git show HEAD:README.md` achou e restaurou mais duas.
5. **Dentro da tolerância?** Sim. A primeira rodada do `close.sh` ficou vermelha em dois portões
   (caminho de home no plano commitado; literal de link no placar), corrigidos em `67e3467`.
6. **Números antes → depois:** `README.md` 179 → 304 linhas, com o essencial nas primeiras ~50 e o
   resto em 4 dobras; READMEs 1 → 2; portões declarados 6 → 7; refutações desta frente 0 → 4;
   afirmações do README que a árvore não sustentava 2 → 0 (mais 1 promovida a manchete, reescrita
   como condicional).
7. **Acervo tocado:** 9 arquivos, +771/−82 em dois commits; criados: `README.pt-BR.md`, este
   handoff, o plano em `done/`; movidos: o plano de `docs/plans/` para `docs/plans/done/` (mesmo
   conteúdo salvo `status:` e `project:`); apagados: nada.
8. **Limite ainda aberto:** o molde do plano pede caminho absoluto e a varredura de privacidade o
   recusa quando o plano é commitado (seção acima); CI deste push só se mede depois dele.
9. **Decisão do dono:** nada; o push está ordenado e sai nesta sessão.
