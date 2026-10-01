#!/usr/bin/env bash
# rite-liveness
# Run alone: bash tests/meta/rite-liveness.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── the rite, end to end: no dead end for the honest act, no way round for the other ─────────
# Every other case fires one hook with one synthetic event. That measures a fence; it does not
# measure the rite. Here whole sessions are simulated (tests/sim/rite-sim.py): each tool call goes
# through every hook hooks/hooks.json registers for it, is EXECUTED in a toy repository if none
# denies, and at the end the repository itself is asked what happened.
#
# Two kinds of session, both in tests/sim/scenarios/:
#   live-*  an honest agent, state after state. Every step says what it expects, and a step
#           denied that should have passed is a DEAD END -- the thing an agent in front of it
#           answers by reaching for the file by hand (field notes of 2026-09-18 and 2026-09-22).
#   att-*   an agent trying to get past the rite. The steps that must be refused say so, and at
#           the end nothing the rite forbids may be true of the repository.
# The first run of the simulator, on 2026-10-01, found two things no case had: with a front open,
# `echo x > outside/b.py` went through the shell; and `git commit -am msg` with nothing staged was
# refused as an empty commit. Both are fixed; both are steps of a scenario now.
section "the rite, end to end (simulated sessions through the real hooks)"
SIM="$ROOT/tests/sim/rite-sim.py"
what_broke() {  # the failure text of a scenario, by what it is about
  case "$1" in
    live-*) echo "the rite has a dead end" ;;
    att-01-*) echo "a front opened from an unapproved scope" ;;
    att-02-*) echo "a change outside the scope was committed, closed over, or never said" ;;
    att-03-*) echo "a forged scope was honoured" ;;
    att-04-*) echo "the agent edited the rites the owner requires" ;;
    *) echo "the rite was got round" ;;
  esac
}
count=0
# RW_SIM_ONLY=<prefix> runs the scenarios whose name starts with it: a refutation needs one.
for scenario in "$ROOT"/tests/sim/scenarios/"${RW_SIM_ONLY:-}"*.json; do
  name="$(basename "$scenario" .json)"
  count=$((count + 1))
  if out="$(python3 "$SIM" "$scenario" 2>&1)"; then
    ok "$name: held ($(printf '%s\n' "$out" | grep -c -E '^ +[0-9]+ ') steps)"
  else
    fail "$(what_broke "$name"): $name
$(printf '%s\n' "$out" | grep -E 'FLAG|UNEXPECTED|RESULT|Traceback|Error' | cut -c1-400 | sed 's/^/          /')"
  fi
done
if [ -n "${RW_SIM_ONLY:-}" ]; then rw_end; fi
[ "$count" -ge 15 ] && ok "$count scenarios ran" || fail "only $count scenarios ran: the directory is not the one the case expects"

# The simulator itself can fail: a scenario in which the rite IS got round has to come back red,
# or every "held" above means nothing. Here the commit guard is switched off by its own option --
# the owner's switch -- and the scenario that commits outside the scope must be reported.
python3 - "$ROOT/tests/sim/scenarios/att-02-writing-outside-the-scope-by-any-means.json" "$TMP/off.json" <<'PY'
import json, sys
j = json.load(open(sys.argv[1]))
j["setup"].setdefault("options", {})["COMMIT_SCOPE"] = "false"
json.dump(j, open(sys.argv[2], "w"))
PY
if out="$(python3 "$SIM" "$TMP/off.json" 2>&1)"; then
  fail "the simulator reported 'held' for a session that committed outside the scope: it cannot see a failure"
else
  printf '%s' "$out" | grep -q 'out_of_scope_committed' && ok "with the commit guard switched off, the same session is reported as broken: the simulator can go red" \
    || fail "the simulator went red for another reason: $(printf '%s' "$out" | tail -3)"
fi
# An untrusted scenario is never run bare.
if command -v sandbox-exec >/dev/null 2>&1; then
  python3 "$SIM" --untrusted "$ROOT/tests/sim/scenarios/live-01-work-inside-an-open-front.json" >/dev/null 2>&1 \
    && ok "an honest scenario also holds inside the write sandbox (--untrusted)" || fail "the write sandbox broke an honest scenario"
else
  echo "  [SKIP] no sandbox-exec on this machine: --untrusted refuses to run, by design"
fi

rw_end
