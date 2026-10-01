#!/usr/bin/env bash
# review-record
# Run alone: bash tests/hooks/review-record.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── review-record: the verdict of a reviewer, written down by the plugin ─────────────────────
# A review used to exist only as what the agent wrote about it. This hook runs when a subagent
# ends and records the verdict line of its report -- who ran, what it said, about which commit and
# tree -- in the project's evidence ledger. The plan gate and the closing read it; this case
# measures the hook itself, and the gate's side of the same acceptance.
# (Measured in a REAL session on 2026-10-01 by tests/bench/bench.sh: the harness hands the hook
# the reviewer's type and final text, and the record is written.)
section "review-record"
RR="$TMP/review-record"; fx_repo_committed "$RR"; RR="$(cd "$RR" && pwd -P)"
RRP="$TMP/review-record-plans"; mkdir -p "$RRP"; printf '# p\n' > "$RRP/the-plan.md"; printf '# q\n' > "$RRP/another.md"
LEDGER="$RR/.roadworthy/evidence.jsonl"
# ended <agent type> <final message> [<cwd>] — the end of a subagent.
ended() {
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SubagentStop","session_id":"sess-1","cwd":sys.argv[3],"agent_id":"a1","agent_type":sys.argv[1],"last_assistant_message":sys.argv[2]}))' "$1" "$2" "${3:-$RR}" > "$TMP/rr-event.json"
  set +e
  OUT="$(env -u ROADWORTHY_DATA CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RRP" bash "$ROOT/hooks/run-hook.cmd" review-record < "$TMP/rr-event.json" 2>"$TMP/err")"; RC=$?
  set -e
}
# last <field> — a field of the last review record.
last() { python3 -c 'import json,sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
rows = [r for r in rows if r.get("kind") == "review"]
v = rows[-1].get(sys.argv[2]) if rows else None
print(",".join(v) if isinstance(v, list) else ("" if v is None else v))' "$LEDGER" "$1"; }
count() { python3 -c 'import json,sys
try: print(sum(1 for l in open(sys.argv[1]) if l.strip() and json.loads(l).get("kind") == "review"))
except FileNotFoundError: print(0)' "$LEDGER"; }

ended roadworthy:cold-reviewer $'Reviewed the-plan.md against its base. Two things hold.\n\nVERDICT: APPROVED'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && ok "the hook says nothing and blocks nothing" || fail "review-record spoke or blocked (exit $RC): $OUT"
[ "$(count)" = 1 ] && [ "$(last verdict)" = APPROVED ] && [ "$(last agent)" = "roadworthy:cold-reviewer" ] \
  && ok "a reviewer that ends with a verdict leaves it on record, with the reviewer's type" || fail "the reviewer's verdict was not recorded: $(cat "$LEDGER" 2>/dev/null)"
[ "$(last head)" = "$(git -C "$RR" rev-parse --short=12 HEAD)" ] && [ -n "$(last wtree)" ] && [ "$(last session)" = "sess-1" ] \
  && ok "with the commit and the tree it was said about, and the session" || fail "the record does not say what the verdict is about: head $(last head), tree $(last wtree)"
[ "$(last plans)" = "the-plan.md" ] && ok "and the plan the report names, so a verdict about one plan is not read as a verdict about another" || fail "the plan the report names was not recorded: '$(last plans)'"

ended roadworthy:cold-reviewer $'Round 1 said VERDICT: APPROVED and I disagree with it now.\n\n> VERDICT: APPROVED\n\n**VERDICT: REJECTED**'
[ "$(last verdict)" = REJECTED ] && ok "the LAST verdict line of the report is the verdict: an earlier round quoted above it is not" || fail "a quoted verdict was taken for the reviewer's own: $(last verdict)"
ended roadworthy:cold-reviewer $'Dois bloqueios não caíram.\n\nVEREDITO: ESCALAR'
[ "$(last verdict)" = ESCALATE ] && ok "the Portuguese words are read (VEREDITO: ESCALAR)" || fail "VEREDITO was not read: $(last verdict)"
ended roadworthy:cold-reviewer $'Tudo confere.\n\nVEREDITO: APROVADO'
[ "$(last verdict)" = APPROVED ] && ok "VEREDITO: APROVADO too" || fail "APROVADO was not read: $(last verdict)"

N="$(count)"
ended roadworthy:cold-reviewer 'I looked around and everything seems fine.'
[ "$(count)" = "$N" ] && ok "a report with no verdict line records nothing" || fail "a report with no verdict was recorded as a review"
ended roadworthy:cold-reviewer $'VERDICT: MAYBE'
[ "$(count)" = "$N" ] && ok "nor does a verdict that is none of the three words" || fail "an unknown verdict word was recorded"
ended roadworthy:cold-reviewer ''
[ "$RC" -eq 0 ] && [ "$(count)" = "$N" ] && ok "an empty final message is no review" || fail "an empty message was recorded, or the hook failed (exit $RC)"

# What another kind of subagent says is recorded as what it is: its type goes in the record, and
# the two readers ask for the reviewer by type.
ended general-purpose $'Looks good to me.\n\nVERDICT: APPROVED'
[ "$(last agent)" = "general-purpose" ] && ok "a verdict from another kind of subagent carries that subagent's type, which the readers refuse" || fail "the record lost the type of the subagent: $(last agent)"

# Outside a repository there is no project to record in, and nothing is created.
NOREPO="$TMP/review-record-nowhere"; mkdir -p "$NOREPO"
ended roadworthy:cold-reviewer $'VERDICT: APPROVED' "$NOREPO"
[ "$RC" -eq 0 ] && [ ! -e "$NOREPO/.roadworthy" ] && ok "outside a repository nothing is recorded and nothing is created" || fail "review-record wrote outside a repository (exit $RC)"

# A ledger that cannot be written never traps the subagent: bookkeeping does not block.
RO="$TMP/review-record-readonly"; fx_repo_committed "$RO"; mkdir -p "$RO/.roadworthy"; chmod 555 "$RO/.roadworthy"
ended roadworthy:cold-reviewer $'VERDICT: APPROVED' "$RO"
chmod 755 "$RO/.roadworthy"
[ "$RC" -eq 0 ] && ok "a ledger that cannot be written does not stop the subagent from ending" || fail "review-record failed on an unwritable ledger (exit $RC): $(cat "$TMP/err")"

# ── 0.7.1: a report handed back through a tool ──────────────────────────────────────────────
# "On Claude Code v2.1.271 or later, a subagent that runs with the SubagentHandback tool delivers
# its report through that tool before it stops. The last_assistant_message field then holds the
# subagent's closing text, if any, which is not the delivered report. The report is that call's
# message input, which a PreToolUse or PostToolUse hook matched on SubagentHandback receives as
# tool_input.message." (hooks reference, read 2026-10-01). Measured the same day: two cold reviews
# in an interactive session, each ending `VERDICT: REJECTED` inside the hand-back, and no record
# of either -- the hook read the closing text, which was empty.
# handed <agent type> <agent id> <report> — the hand-back, as the PostToolUse event of that tool.
handed() {
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","tool_name":"SubagentHandback","session_id":"sess-1","cwd":sys.argv[4],"agent_id":sys.argv[2],"agent_type":sys.argv[1],"tool_input":{"message":sys.argv[3]},"tool_response":"delivered"}))' "$1" "$2" "$3" "$RR" > "$TMP/rr-event.json"
  set +e
  OUT="$(env -u ROADWORTHY_DATA CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RRP" bash "$ROOT/hooks/run-hook.cmd" review-record < "$TMP/rr-event.json" 2>"$TMP/err")"; RC=$?
  set -e
}
# stopped <agent type> <agent id> <closing text> [<the subagent's own transcript>] — its end.
stopped() {
  python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"SubagentStop","session_id":"sess-1","cwd":sys.argv[5],"agent_id":sys.argv[2],"agent_type":sys.argv[1],"last_assistant_message":sys.argv[3],"agent_transcript_path":sys.argv[4]}))' "$1" "$2" "$3" "${4:-}" "$RR" > "$TMP/rr-event.json"
  set +e
  OUT="$(env -u ROADWORTHY_DATA CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RRP" bash "$ROOT/hooks/run-hook.cmd" review-record < "$TMP/rr-event.json" 2>"$TMP/err")"; RC=$?
  set -e
}
N="$(count)"
handed roadworthy:cold-reviewer h1 $'Reviewed the-plan.md against the criteria. Two blockers.\n\nVERDICT: REJECTED'
[ "$RC" -eq 0 ] && [ -z "$OUT" ] && [ "$(count)" = "$((N + 1))" ] && [ "$(last verdict)" = REJECTED ] && [ "$(last agent)" = "roadworthy:cold-reviewer" ] \
  && ok "a report handed back through the tool leaves the reviewer's verdict on record" || fail "a report handed back by tool left no record (count $(count), was $N; exit $RC): $OUT"
[ "$(last event)" = PostToolUse ] && [ "$(last agent_id)" = h1 ] && [ "$(last plans)" = "the-plan.md" ] && [ -n "$(last wtree)" ] \
  && ok "with the event it came by, the subagent it came from, the plan it names and the tree" || fail "the hand-back record does not say where it came from: event '$(last event)', agent_id '$(last agent_id)'"
# The same subagent then ENDS. Its closing text is not the report, and the report is already on
# record: nothing is written twice, whether the closing text is empty or repeats the verdict.
N="$(count)"
stopped roadworthy:cold-reviewer h1 ''
stopped roadworthy:cold-reviewer h1 $'Report delivered.\n\nVERDICT: REJECTED'
[ "$(count)" = "$N" ] && ok "the end of a subagent whose hand-back is on record writes nothing more" || fail "the same review was recorded twice (count $(count), was $N)"
# The second way to the same report: the subagent's own transcript, which the harness names in the
# event (`agent_transcript_path`). The shape is the one measured in the two reviews of 2026-10-01:
# an assistant record whose content carries a `tool_use` named SubagentHandback, with the report
# in `input.message`, and no closing text after it.
python3 -c 'import json,sys
rows = [{"type": "user", "message": {"role": "user", "content": "review it"}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "text", "text": "Reading the diff."}]}},
        {"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "SubagentHandback", "input": {"message": "Reviewed another.md. It holds.\n\nVERDICT: APPROVED"}}]}},
        {"type": "user", "message": {"role": "user", "content": [{"type": "tool_result", "content": "ok"}]}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))' "$TMP/agent-h2.jsonl"
N="$(count)"
stopped roadworthy:cold-reviewer h2 '' "$TMP/agent-h2.jsonl"
[ "$(count)" = "$((N + 1))" ] && [ "$(last verdict)" = APPROVED ] && [ "$(last agent_id)" = h2 ] && [ "$(last plans)" = "another.md" ] \
  && ok "a subagent that ends with no closing text is read from its own transcript: the hand-back found there is the report" || fail "a hand-back found only in the subagent's transcript left no record (count $(count), was $N)"
N="$(count)"
stopped roadworthy:cold-reviewer h3 '' "$TMP/does-not-exist.jsonl"
[ "$RC" -eq 0 ] && [ "$(count)" = "$N" ] && ok "and a transcript that is not there records nothing and stops nobody" || fail "a missing transcript was recorded, or the hook failed (exit $RC)"
# A hand-back that does not say WHO handed it back. `agent_type` is "present when ... the hook fires
# inside a subagent" by the reference; nothing measured yet says the hand-back event carries it in
# an interactive session. Both readers of the record ask for the reviewer by name, so a nameless
# record is useless to them -- and, once on record, it kept the named one out when the subagent
# ended (cold review of the 0.7.1 diff, 2026-10-01). A nameless hand-back writes nothing; the end
# of the subagent, which names it, reads the report from the transcript.
python3 -c 'import json,sys
rows = [{"type": "assistant", "message": {"role": "assistant", "content": [{"type": "tool_use", "name": "SubagentHandback", "input": {"message": "Reviewed the-plan.md. It holds.\n\nVERDICT: APPROVED"}}]}}]
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))' "$TMP/agent-h4.jsonl"
N="$(count)"
handed '' h4 $'Reviewed the-plan.md. It holds.\n\nVERDICT: APPROVED'
stopped roadworthy:cold-reviewer h4 '' "$TMP/agent-h4.jsonl"
[ "$(count)" = "$((N + 1))" ] && [ "$(last agent)" = "roadworthy:cold-reviewer" ] && [ "$(last event)" = SubagentStop ] \
  && ok "a hand-back that does not name its subagent writes nothing, and the end of that subagent records the review with the name" || fail "a hand-back with no reviewer's name kept the named record out (count $(count), was $N; agent '$(last agent)', event '$(last event)')"

# The other half of the acceptance: the plan gate refuses a review file with no such record.
section "review-record (what the plan gate does with it)"
GP="$TMP/review-record-gate"; fx_repo_committed "$GP"; GP="$(cd "$GP" && pwd -P)"
GPP="$TMP/review-record-gate-plans"; mkdir -p "$GPP"
printf '# A plan\n\nproject: %s\n\n## Goal\n' "$GP" > "$GPP/g.md"
printf 'plan: g.md\nround: 1\nVERDICT: APPROVED\n' > "$GPP/g.review.md"
gate() { CLAUDE_PLUGIN_OPTION_PLAN_GATE=review CLAUDE_PLUGIN_OPTION_PLANS_DIR="$GPP" run_hook plan-review-gate "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"ExitPlanMode","cwd":sys.argv[1],"tool_input":{}}))' "$GP")"; }
gate
denied && printf '%s' "$OUT" | grep -q 'none is on record' && ok "a review file with no reviewer's verdict behind it is refused by the plan gate" || fail "a review nobody ran was accepted: $OUT"
ended roadworthy:cold-reviewer $'Reviewed g.md.\n\nVERDICT: APPROVED' "$GP"
gate
! denied && ok "and passes once the reviewer ended with APPROVED, recorded by this hook" || fail "a recorded approval was not found by the plan gate (a dead end): $OUT"

rw_end
