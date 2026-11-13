#!/usr/bin/env bash
# principles
# Run alone: bash tests/hooks/principles.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── principles ───────────────────────────────────────────────────────────────
section "principles (UserPromptSubmit)"
PROJ="$HOME_SANDBOX/.claude/projects/-tmp-proj"; mkdir -p "$PROJ/memory"
printf '# index\n1. Project rule one → [detail](feedback_one.md)\n- not a rule\n2. Project rule two\n' > "$PROJ/memory/MEMORY.md"
: > "$PROJ/memory/feedback_one.md"
run_hook principles "{\"transcript_path\":\"$PROJ/s.jsonl\",\"cwd\":\"/tmp\",\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"hi\"}"
[ "$RC" -eq 0 ] && [ -z "$ERR" ] && ok "exit 0, silent stderr" || fail "principles rc=$RC err=$ERR"
n_general="$(context | awk '/^ROADWORTHY PRINCIPLES/{s=1;next} /^PROJECT RULES/{s=0} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
n_project="$(context | awk '/^PROJECT RULES/{s=1;next} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
[ "$n_general" = "8" ] && ok "8 bundled principles injected (only rules with a mechanism behind them)" || fail "bundled principles: $n_general"
[ "$n_project" = "2" ] && ok "2 project rules injected, prose skipped" || fail "project rules: $n_project"
CTX="$(context)"; printf '%s' "$CTX" | grep -q "](${PROJ}/memory/feedback_one.md)" && ok "relative link rewritten to absolute" || fail "link rewrite"
run_hook principles "{\"transcript_path\":\"$HOME_SANDBOX/.claude/projects/-none/s.jsonl\"}"
[ "$(context | grep -c '^PROJECT RULES')" = "0" ] && ok "no memory dir → general layer only" || fail "unexpected project layer"
CLAUDE_PLUGIN_OPTION_PROJECT_RULES=false run_hook principles "{\"transcript_path\":\"$PROJ/s.jsonl\"}"
[ "$(context | grep -c '^PROJECT RULES')" = "0" ] && ok "project_rules=false honoured" || fail "project_rules=false"
printf '1. Only mine\n' > "$TMP/mine.md"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$TMP/mine.md" run_hook principles '{"transcript_path":""}'
[ "$(context | grep -c '^1\. Only mine')" = "1" ] && ok "principles_file override" || fail "principles_file override"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$TMP/missing.md" run_hook principles '{"transcript_path":""}'
[ "$RC" -eq 1 ] && [ -z "$OUT" ] && [ -n "$ERR" ] && ok "missing principles file → exit 1 + notice, never 2" || fail "missing file rc=$RC"
run_hook principles 'not json'
[ "$RC" -eq 1 ] && [ -n "$ERR" ] && ok "malformed stdin → exit 1 + notice" || fail "malformed stdin rc=$RC"
# The principles file lives OUTSIDE every repository and is shared by every project, so nothing
# here can stop it being edited -- not protect-paths, which only builds a path inside the session
# directory, not the entry gate, which only denies inside a repository. What a mechanism CAN do is
# refuse to let the change pass unannounced, at every prompt, until the owner agrees to it.
PIND="$TMP/pindata"; PINF="$TMP/pinned-principles.md"; mkdir -p "$PIND"
printf '1. One.\n2. Two.\n' > "$PINF"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
CTX1="$(context)"
printf '%s' "$CTX1" | grep -q 'CHANGED SINCE' && fail "warned on the first sight of a file" || ok "the first sight of a principles file pins it, silently"
printf '1. One.\n2. Two, edited.\n' > "$PINF"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
CTX2="$(context)"
printf '%s' "$CTX2" | grep -q 'THE PRINCIPLES FILE CHANGED' && ok "an edit to the principles file is announced in the prompt" || fail "a silent edit to the principles file"
printf '%s' "$CTX2" | grep -q 'agreed:' && ok "and the notice names the digest and the date last agreed" || fail "the notice does not say what was agreed: $CTX2"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF" ROADWORTHY_DATA="$PIND" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
printf '%s' "$(context)" | grep -q 'THE PRINCIPLES FILE CHANGED' && ok "and it repeats every prompt: it is not a one-off that scrolls away" || fail "the notice appeared once and vanished"
# A fence that keeps denying the same way becomes a line in the next prompt. An agent does not
# remember, but it reads -- this is the only kind of consequence that reaches the following turn.
DENR="$TMP/denyrepo"; DEND="$TMP/denydata"; mkdir -p "$DENR/.roadworthy" "$DEND"; git -C "$DENR" init -q
printf 'src/**\n' > "$DENR/.roadworthy/scope"
for i in 1 2; do
  ROADWORTHY_DATA="$DEND" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"d1\",\"cwd\":\"$DENR\",\"tool_input\":{\"file_path\":\"$DENR/out$i.md\"}}"
done
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"session_id\":\"d1\",\"cwd\":\"$DENR\"}"
printf '%s' "$(context)" | grep -q 'HAS DENIED THE SAME WAY' && fail "two denials already counted as a pattern" || ok "two denials are not yet a pattern"
ROADWORTHY_DATA="$DEND" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"d1\",\"cwd\":\"$DENR\",\"tool_input\":{\"file_path\":\"$DENR/out3.md\"}}"
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"session_id\":\"d1\",\"cwd\":\"$DENR\"}"
CTX3="$(context)"
printf '%s' "$CTX3" | grep -q 'HAS DENIED THE SAME WAY' && ok "the third denial by the same fence comes back as a line in the prompt" || fail "three denials did not become a rule"
printf '%s' "$CTX3" | grep -q 'scope-lock: 3 denials' && ok "and it names the fence and the count" || fail "the injected line does not name the fence: $CTX3"
# It must not be a numbered line: those are the principles, and the suite counts them.
n_after="$(printf '%s' "$CTX3" | awk '/^ROADWORTHY PRINCIPLES/{s=1;next} /^PROJECT RULES|^A FENCE/{s=0} s' | grep -c -E '^[0-9]+[a-z]*\. ' || true)"
[ "$n_after" = "8" ] && ok "the injected line is not a numbered principle (still eight)" || fail "the count line became a principle: $n_after"
[ -f "$DEND/denials.jsonl" ] && python3 -c 'import json,sys
r = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
sys.exit(0 if {"ts","hook","reason","cwd","front"} <= set(r) and r["hook"] == "scope-lock" else 1)' "$DEND/denials.jsonl" \
  && ok "every denial is recorded with the fence, the reason and the front" || fail "no usable denial record"
# THE SAME FIELD CASE, on this ledger. Claude Code hands every hook CLAUDE_PLUGIN_DATA, per plugin
# and shared by every project; the assertions above set ROADWORTHY_DATA and so never ran the way
# the harness runs. Measured on 2026-09-14: six real denials of the day were in the shared plugin
# directory, the reader looked in the project, and the line "A FENCE HAS DENIED" had never once
# reached a prompt. Here nothing sets ROADWORTHY_DATA; only the harness's variable is set.
PDR="$TMP/pdrepo"; PDD="$TMP/pdplugindata"; mkdir -p "$PDR/.roadworthy" "$PDD"; git -C "$PDR" init -q
printf 'src/**\n' > "$PDR/.roadworthy/scope"
for i in 1 2 3; do
  CLAUDE_PLUGIN_DATA="$PDD" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"p1\",\"cwd\":\"$PDR\",\"tool_input\":{\"file_path\":\"$PDR/out$i.md\"}}"
done
[ -f "$PDR/.roadworthy/denials.jsonl" ] && [ ! -f "$PDD/denials.jsonl" ] \
  && ok "a denial is recorded in the PROJECT ledger with only CLAUDE_PLUGIN_DATA set, as in the harness" || fail "the denial went to the shared plugin directory"
CLAUDE_PLUGIN_DATA="$PDD" run_hook principles "{\"transcript_path\":\"\",\"session_id\":\"p1\",\"cwd\":\"$PDR\"}"
printf '%s' "$(context)" | grep -q 'HAS DENIED THE SAME WAY' \
  && ok "and the third denial reaches the prompt: the writer and the reader agree on the ledger" || fail "the writer and the reader disagree on the ledger"
# The pin of the principles file is the one thing that stays in the shared directory: the file
# lives outside every repository, so its digest cannot live in one of them.
PINF2="$TMP/pinned2.md"; printf '1. One.\n' > "$PINF2"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF2" CLAUDE_PLUGIN_DATA="$PDD" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
[ -n "$(find "$PDD" -maxdepth 1 -name 'principles.*.json' -print -quit)" ] \
  && ok "the pin of the principles file stays in CLAUDE_PLUGIN_DATA: global by construction" || fail "the pin left the shared directory"

# ── 0.7.0: a denial has an owner ──────────────────────────────────────────────
# The count looked at every record carrying the front's name. Denials of a subagent, of another
# session and from before the front were all charged to the main agent, and the warning never
# expired (field note, 2026-09-30: "rite-gate: 4 denials" shown to a session denied once).
section "principles (whose denials are counted, and until when)"
WH="$TMP/whose"; WHD="$TMP/whose-data"; mkdir -p "$WH/.roadworthy" "$WHD"; git -C "$WH" init -q
printf 'src/**\n' > "$WH/.roadworthy/scope"
whd() { ROADWORTHY_DATA="$WHD" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"$1\",\"cwd\":\"$WH\",\"tool_input\":{\"file_path\":\"$WH/out-$RANDOM.md\"}$2}"; }
whp() { ROADWORTHY_DATA="$WHD" run_hook principles "{\"transcript_path\":\"\",\"session_id\":\"$1\",\"cwd\":\"$WH\"}"; context; }
for i in 1 2 3 4; do whd main ',"agent_id":"agent-7"'; done
whp main | grep -q 'HAS DENIED THE SAME WAY' && fail "a subagent denial was charged to the front" || ok "four denials of a subagent are not the main agent's three strikes"
for i in 1 2 3; do whd other ''; done
whp main | grep -q 'HAS DENIED THE SAME WAY' && fail "a subagent denial was charged to the front (another session's, in fact)" || ok "nor are three denials of another session"
whd main ''; whd main ''
whp main | grep -q 'HAS DENIED THE SAME WAY' && fail "two denials already counted as a pattern" || ok "two of its own are not yet a pattern"
whd main ''
denied && printf '%s' "$OUT" | grep -q 'HAS NOW DENIED THE SAME WAY 3 TIMES' \
  && ok "the third carries the warning in its own reason, in the same turn" || fail "the third denial did not say so in its own reason: $OUT"
whp main | grep -q 'scope-lock: 3 denials' && ok "and the next prompt says it too, with the right count" || fail "the count is not this agent's: $(whp main | tail -5)"
rm -f "$WH/.roadworthy/scope"
whp main | grep -q 'HAS DENIED THE SAME WAY' && fail "the warning outlived the front" || ok "with the front closed there is no warning, and no line was deleted for that ($(wc -l < "$WHD/denials.jsonl" | tr -d ' ') records kept)"

# ── 0.7.0: the reporting form agreed for the front reaches every prompt ──────
section "principles (the reporting form the owner agreed)"
RF="$TMP/report-form"; mkdir -p "$RF/src"; git -C "$RF" init -q; git -C "$RF" config user.email t@t; git -C "$RF" config user.name t
printf 'a\n' > "$RF/src/a.py"
printf '# P\n\nreport: prose, the conclusion first; a table only for three or more items with proof\n\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$RF/plan.md"
git -C "$RF" add -A; git -C "$RF" commit -q -m base
(cd "$RF" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plan.md) >/dev/null
rfp() { env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" principles <<< "{\"transcript_path\":\"\",\"session_id\":\"r1\",\"cwd\":\"$RF\"}" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
rfp | grep -q 'REPORTING FORM AGREED' && rfp | grep -q 'a table only for three or more items with proof' \
  && ok "while the front is open, the form agreed in the plan is said at every prompt" || fail "the agreed reporting form did not reach the prompt"
rm -f "$RF/.roadworthy/scope"
rfp | grep -q 'REPORTING FORM AGREED' && fail "the agreed reporting form outlived the front" || ok "closed, it stops"
printf '# P\n## Scope\n```\nsrc/**\n```\n## Verification\n```\ntrue\n```\n' > "$RF/plain.md"
(cd "$RF" && bash "$ROOT/skills/plan/scripts/scope-write.sh" plain.md) >/dev/null
rfp | grep -q 'REPORTING FORM AGREED' && fail "a plan with no report line injected one" || ok "a plan that declares none injects none: the default is the plugin's, written in the template"

# ── 0.7.0: a person's answer is read from the person's prompt ────────────────
section "principles (a human verification answered in the prompt)"
HP="$TMP/human-prompt"; mkdir -p "$HP/.roadworthy"; git -C "$HP" init -q; git -C "$HP" config user.email t@t; git -C "$HP" config user.name t
printf 'true\n' > "$HP/.roadworthy/gates"; printf 'x\n' > "$HP/f"; git -C "$HP" add -A; git -C "$HP" commit -q -m base
(cd "$HP" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh" --needs-human "the label on the device") >/dev/null
(cd "$HP" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh" --needs-human "colour bands") >/dev/null
hpp() { python3 -c 'import json,sys; print(json.dumps({"transcript_path":"","session_id":"h1","cwd":sys.argv[1],"prompt":sys.argv[2]}))' "$HP" "$1" | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" principles | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
hps() { (cd "$HP" && env -u ROADWORTHY_DATA bash "$ROOT/skills/close/scripts/close.sh" --state); }
HPO="$(hpp $'I checked the device.\nrw-human: the label on the device approved')"
printf '%s' "$HPO" | grep -q 'THE OWNER ANSWERED' && [ "$(hps)" = "needs_human" ] \
  && ok "a line in the owner's prompt records the answer; one item still open keeps needs_human" || fail "the owner's answer in the prompt was not recorded: $HPO / $(hps)"
HPO="$(hpp 'rw-human: colour bands rejected the hue is wrong')"
[ "$(hps)" = "gaps_found" ] && grep -q 'the hue is wrong' "$HP/.roadworthy/evidence.jsonl" && grep -q 'the owner, in the prompt' "$HP/.roadworthy/evidence.jsonl" \
  && ok "a rejection is recorded with its note and with who said it" || fail "the rejection in the prompt was not recorded: $HPO / $(hps)"
HPO="$(hpp 'please tell me about rw-human: lines')"
printf '%s' "$HPO" | grep -q 'THE OWNER ANSWERED' && fail "a prompt that only mentions the marker was taken for an answer" || ok "a prompt that mentions the marker mid-sentence is not an answer"
HPO="$(hpp 'rw-human: no such item approved')"
printf '%s' "$HPO" | grep -q 'could not be recorded' && ok "an answer about an item nobody opened is said back, not swallowed" || fail "a failed answer was silent: $HPO"

# ── 0.8.0: the owner closes a front with one word, in the chat ───────────────────────────────
# The closing of a front the rite opened waits for the owner. The answer is a word of the owner's
# own prompt -- `aprovado`, `aprovada`, `approved`, or `reprovado <reason>` -- when exactly one
# closing is waiting and it is the live front's. Two repositories here, and the session stands in
# the SECOND one, which is where the measured refusals happened.
section "principles (the owner's word closes the front)"
WA="$TMP/word-a"; fx_repo_committed "$WA"; WA="$(cd "$WA" && pwd -P)"; mkdir -p "$WA/src"; printf 'a\n' > "$WA/src/a.py"; git -C "$WA" add -A; git -C "$WA" commit -q -m src
WB="$TMP/word-b"; fx_repo_committed "$WB"; WB="$(cd "$WB" && pwd -P)"; mkdir -p "$WB/lib"; printf 'b\n' > "$WB/lib/b.py"; git -C "$WB" add -A; git -C "$WB" commit -q -m lib
printf '# P\n## Scope\n```\nsrc/**\n%s/lib/**\n```\n## Verification\n```\ntrue\ncd %s && true\n```\n' "$WB" "$WB" > "$TMP/word-plan.md"
WCLOSE="$ROOT/skills/close/scripts/close.sh"
w_open() { (cd "$WA" && bash "$ROOT/skills/plan/scripts/scope-write.sh" "$TMP/word-plan.md") >/dev/null; }
w_close() { (cd "$WA" && env -u ROADWORTHY_DATA bash "$WCLOSE") >/dev/null 2>&1 || true; }
w_state() { (cd "$1" && env -u ROADWORTHY_DATA bash "$WCLOSE" --state); }
# w_say <cwd> <prompt> — what the hook hands back to the agent for that prompt of the owner
w_say() { python3 -c 'import json,sys; print(json.dumps({"transcript_path":"","session_id":"w1","cwd":sys.argv[1],"hook_event_name":"UserPromptSubmit","prompt":sys.argv[2]}))' "$1" "$2" | env -u ROADWORTHY_DATA bash "$ROOT/hooks/run-hook.cmd" principles | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
w_open; for r in "$WA" "$WB"; do git -C "$r" add .roadworthy/gates; git -C "$r" commit -q -m 'the gates of the front'; done
printf 'b2\n' > "$WB/lib/b.py"; git -C "$WB" commit -q -am work
w_close
[ "$(w_state "$WA")" = "needs_human" ] || fail "the fixture: the closing is not waiting for the owner ($(w_state "$WA"))"
WO="$(w_say "$WB" 'acho que está aprovado, mas olhe o texto antes')"
[ -f "$WA/.roadworthy/scope" ] && ok "the word in the middle of a sentence is conversation, not an order" || fail "a sentence that only contains the word closed the front: $WO"
WO="$(w_say "$WB" 'aprovado')"
[ ! -f "$WA/.roadworthy/scope" ] && [ ! -f "$WB/.roadworthy/scope" ] && [ "$(w_state "$WA")$(w_state "$WB")" = "passedpassed" ] \
  && ok "the owner's 'aprovado', with the session standing in the second repository, closes the front in both" || fail "the owner's approval in the prompt did not close the front: $(w_state "$WA")/$(w_state "$WB"): $WO"
printf '%s' "$WO" | grep -q 'THE OWNER' && ok "and the agent is told what the owner's word did" || fail "the owner's approval was silent to the agent: $WO"
WO="$(w_say "$WB" 'aprovado')"
printf '%s' "$WO" | grep -q 'THE OWNER' && fail "the word with no closing waiting was taken for an order: $WO" || ok "with no closing waiting, the same word is only a word"
# The tree changed after the gates: recorded, and the front stays open.
w_open; w_close
printf 'b3\n' > "$WB/lib/b.py"; git -C "$WB" commit -q -am 'changed after the gates'
WO="$(w_say "$WA" 'Aprovado.')"
[ -f "$WA/.roadworthy/scope" ] && [ -f "$WB/.roadworthy/scope" ] && printf '%s' "$WO" | grep -q -i 'again' \
  && ok "an approval after the tree changed is recorded, closes nothing and sends the closing to run again" || fail "an approval closed a tree the gates never measured: $WO"
w_close
WO="$(w_say "$WB" 'reprovado o texto da ajuda está errado')"
[ -f "$WA/.roadworthy/scope" ] && [ -f "$WB/.roadworthy/scope" ] && [ "$(w_state "$WA")" = "gaps_found" ] && grep -q 'o texto da ajuda está errado' "$WA/.roadworthy/evidence.jsonl" \
  && ok "'reprovado <motivo>' keeps the scope, records gaps_found and the reason" || fail "a rejection released the scope or lost its reason: $(w_state "$WA"): $WO"
w_close
WO="$(w_say "$WA" 'rw-human: aprovado')"
[ ! -f "$WA/.roadworthy/scope" ] && [ ! -f "$WB/.roadworthy/scope" ] && ok "the line 'rw-human: aprovado' closes it too" || fail "the owner's approval in the prompt did not close the front (rw-human line): $WO"

# ── 0.8.0: the owner's acts pass through the chat ─────────────────────────────────────────────
# Two acts were the owner's and could only be done OUTSIDE the agent, by hand: agreeing to a
# principles file that changed (rewriting its pin), and changing the files the fences read to
# guard against the agent. Both are lines of the owner's own prompt now, at the start of a line:
#     rw-principios: aceito
#     rw-config: [<repository>] <file> + <line>      (- <line> removes it)
#     rw-config: [<repository>] docs.json <key> = <value>
section "principles (the owner's acts, in the chat)"
OC="$TMP/owner-chat"; fx_repo_committed "$OC"; OC="$(cd "$OC" && pwd -P)"
OC2="$TMP/owner-chat-other"; fx_repo_committed "$OC2"; OC2="$(cd "$OC2" && pwd -P)"
OPF="$TMP/owner-principles.md"; OPD="$TMP/owner-pin"; printf '1. one rule\n' > "$OPF"
# o_say <prompt> — what the hook says for that prompt, with the session standing in $OC
o_say() { python3 -c 'import json,sys; print(json.dumps({"transcript_path":"","session_id":"o1","cwd":sys.argv[1],"hook_event_name":"UserPromptSubmit","prompt":sys.argv[2]}))' "$OC" "$1" | CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$OPF" ROADWORTHY_DATA="$OPD" bash "$ROOT/hooks/run-hook.cmd" principles | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }
o_say 'hello' >/dev/null                                   # the first sight pins the file
printf '1. one rule\n2. a rule somebody added\n' > "$OPF"
OO="$(o_say 'what changed?')"
printf '%s' "$OO" | grep -q 'CHANGED SINCE' || fail "the fixture: a changed principles file is not announced"
printf '%s' "$OO" | grep -q 'rw-principios: aceito' && ok "the notice of a changed principles file says how the owner agrees to it: a line in the chat" || fail "the notice still sends the owner to edit the pin by hand: $OO"
OO="$(o_say 'eu ainda não escrevi rw-principios: aceito, só estou perguntando')"
printf '%s' "$OO" | grep -q 'CHANGED SINCE' && ok "the marker in the middle of a sentence agrees to nothing" || fail "a line that is not the owner's order changed a file: the pin was updated from the middle of a sentence"
OO="$(o_say $'li o arquivo novo.\nrw-principios: aceito')"
printf '%s' "$OO" | grep -q 'THE OWNER ACCEPTED' && ! printf '%s' "$OO" | grep -q 'CHANGED SINCE' \
  && ok "'rw-principios: aceito' pins the new text, and says so" || fail "the owner's acceptance did not update the pin: $OO"
OO="$(o_say 'and now?')"
printf '%s' "$OO" | grep -q 'CHANGED SINCE' && fail "the owner's acceptance did not update the pin: the notice came back at the next prompt" || ok "and the notice is silent from then on"
# The owner's files.
OO="$(o_say 'rw-config: protected + lib/auth/**')"
[ "$(cat "$OC/.roadworthy/protected" 2>/dev/null)" = 'lib/auth/**' ] && printf '%s' "$OO" | grep -q 'THE OWNER CHANGED' \
  && ok "'rw-config: protected + <glob>' adds the line to the owner's file, and says so" || fail "the owner's line in the prompt did not change the file: $(cat "$OC/.roadworthy/protected" 2>&1) / $OO"
o_say 'rw-config: protected + secrets/**' >/dev/null; o_say 'rw-config: protected + lib/auth/**' >/dev/null
[ "$(cat "$OC/.roadworthy/protected")" = "$(printf 'lib/auth/**\nsecrets/**')" ] && ok "a second line is added after the first, and one already there is not repeated" || fail "the owner's line in the prompt did not change the file as asked: $(tr '\n' '|' < "$OC/.roadworthy/protected")"
OO="$(o_say 'rw-config: protected - lib/auth/**')"
[ "$(cat "$OC/.roadworthy/protected")" = 'secrets/**' ] && ok "the same line with '-' removes it" || fail "the owner's line in the prompt did not change the file (removal): $(tr '\n' '|' < "$OC/.roadworthy/protected") / $OO"
OO="$(o_say 'rw-config: protected - never/was/here')"
[ "$(cat "$OC/.roadworthy/protected")" = 'secrets/**' ] && printf '%s' "$OO" | grep -q -i 'not there' && ok "removing a line that is not there changes nothing and says so" || fail "a removal of a line that is not there was silent, or wrote: $OO"
OO="$(o_say 'rw-config: rites + owner_approval: off')"; o_say 'rw-config: rites + plan_gate: both' >/dev/null; o_say 'rw-config: rites + plan_gate: review' >/dev/null
[ "$(cat "$OC/.roadworthy/rites")" = "$(printf 'owner_approval: off\nplan_gate: review')" ] && ok "in the rites a key is SET: saying it again with another value replaces the line" || fail "the owner's line in the prompt did not change the file (rites): $(tr '\n' '|' < "$OC/.roadworthy/rites")"
for f in free overnight-rules standing-gates; do
  o_say "rw-config: $f + x-$f" >/dev/null
  [ "$(cat "$OC/.roadworthy/$f" 2>/dev/null)" = "x-$f" ] || fail "the owner's line in the prompt did not change the file: $f"
done
ok "free, overnight-rules and standing-gates are written the same way"
OO="$(o_say 'rw-config: docs.json plans = docs/plans')"; o_say 'rw-config: docs.json status.superseded by = superado por' >/dev/null
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d == {"plans": "docs/plans", "status": {"superseded by": "superado por"}} else 1)' "$OC/.roadworthy/docs.json" \
  && ok "docs.json takes 'key = value', a dotted key going one level in, and stays valid JSON" || fail "the owner's line in the prompt did not change the file (docs.json): $(cat "$OC/.roadworthy/docs.json" 2>&1) / $OO"
OO="$(o_say "rw-config: $OC2 free + notes/**")"
[ "$(cat "$OC2/.roadworthy/free" 2>/dev/null)" = 'notes/**' ] && ! grep -q 'notes' "$OC/.roadworthy/free" \
  && ok "with a repository named, the line goes to that repository's file" || fail "the owner's line in the prompt did not change the file of the repository it named: $OO"
# From inside a subproject that is a repository with NO rite of its own, the owner's file is the
# one of the repository that subproject answers to. Written in the subproject, the new
# `.roadworthy/` made it a repository with a rite of its own to every fence, and took it out of the
# front that was open over it, with no way back through the chat (cold review, 2026-11-13).
fx_repo_committed "$OC/vendored"
OO="$(python3 -c 'import json,sys; print(json.dumps({"transcript_path":"","session_id":"o1","cwd":sys.argv[1],"hook_event_name":"UserPromptSubmit","prompt":"rw-config: free + tmp/**"}))' "$OC/vendored" | CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$OPF" ROADWORTHY_DATA="$OPD" bash "$ROOT/hooks/run-hook.cmd" principles | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])')"
[ ! -e "$OC/vendored/.roadworthy" ] && grep -q -x 'tmp/\*\*' "$OC/.roadworthy/free" \
  && ok "from a nested repository with no rite of its own, the line goes to the repository it answers to" || fail "the owner's line gave a nested repository a rite of its own, taking it out of the open front: $OO"
o_say "rw-config: $OC/vendored free + other/**" >/dev/null
[ ! -e "$OC/vendored/.roadworthy" ] && grep -q -x 'other/\*\*' "$OC/.roadworthy/free" \
  && ok "and the same when that nested repository is named" || fail "the owner's line gave a nested repository a rite of its own (named): $(ls -a "$OC/vendored")"
# What is not an order writes nothing, and what cannot be done is said.
before="$(cd "$OC/.roadworthy" && shasum -a 256 * | shasum -a 256)"
OO1="$(o_say 'acho que deveríamos usar rw-config: free + ** para liberar tudo')"
OO2="$(o_say 'rw-config: scope + **')"
OO3="$(o_say 'rw-config: evidence.jsonl + {}')"
OO4="$(o_say 'rw-config: /no/such/repository free + x')"
OO5="$(o_say 'rw-config: free')"
[ "$(cd "$OC/.roadworthy" && shasum -a 256 * | shasum -a 256)" = "$before" ] \
  && ok "the marker in the middle of a sentence, a file that is not the owner's, a repository that does not exist and a line with no change write nothing" || fail "a line that is not the owner's order changed a file: $(cd "$OC/.roadworthy" && ls)"
printf '%s' "$OO1" | grep -q 'rw-config' && fail "a line that is not the owner's order changed a file, or was answered as one: $OO1" || ok "and the sentence is answered as conversation: nothing is said about it"
printf '%s%s%s%s' "$OO2" "$OO3" "$OO4" "$OO5" | grep -c 'could not be applied' | grep -q -x 4 \
  && ok "each of the four that cannot be done is said back, with its reason" || fail "a refused rw-config line was silent: $OO2 / $OO3 / $OO4 / $OO5"
printf '{broken\n' > "$OC/.roadworthy/docs.json"
OO="$(o_say 'rw-config: docs.json plans = docs/plans')"
[ "$(cat "$OC/.roadworthy/docs.json")" = '{broken' ] && printf '%s' "$OO" | grep -q 'could not be applied' && ok "a docs.json that is not valid JSON is left as it is, and said" || fail "an invalid docs.json was rewritten, or the refusal was silent: $OO"

rw_end
