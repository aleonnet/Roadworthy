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
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"cwd\":\"$DENR\"}"
printf '%s' "$(context)" | grep -q 'HAS DENIED THE SAME WAY' && fail "two denials already counted as a pattern" || ok "two denials are not yet a pattern"
ROADWORTHY_DATA="$DEND" run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"d1\",\"cwd\":\"$DENR\",\"tool_input\":{\"file_path\":\"$DENR/out3.md\"}}"
ROADWORTHY_DATA="$DEND" run_hook principles "{\"transcript_path\":\"\",\"cwd\":\"$DENR\"}"
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
CLAUDE_PLUGIN_DATA="$PDD" run_hook principles "{\"transcript_path\":\"\",\"cwd\":\"$PDR\"}"
printf '%s' "$(context)" | grep -q 'HAS DENIED THE SAME WAY' \
  && ok "and the third denial reaches the prompt: the writer and the reader agree on the ledger" || fail "the writer and the reader disagree on the ledger"
# The pin of the principles file is the one thing that stays in the shared directory: the file
# lives outside every repository, so its digest cannot live in one of them.
PINF2="$TMP/pinned2.md"; printf '1. One.\n' > "$PINF2"
CLAUDE_PLUGIN_OPTION_PRINCIPLES_FILE="$PINF2" CLAUDE_PLUGIN_DATA="$PDD" run_hook principles '{"transcript_path":"","cwd":"/tmp"}'
[ -n "$(find "$PDD" -maxdepth 1 -name 'principles.*.json' -print -quit)" ] \
  && ok "the pin of the principles file stays in CLAUDE_PLUGIN_DATA: global by construction" || fail "the pin left the shared directory"

rw_end
