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

rw_end
