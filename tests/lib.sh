#!/usr/bin/env bash
# The shared half of the suite: what every case needs and nothing a case owns.
#
# Until 0.6.0 this was the first fifty lines of a 1407-line tests/run.sh, and every one of the 36
# sections lived in the same shell. That had a measured cost: a section could not be run alone, so
# a refutation -- inject the defect, watch the check go red -- had to run the WHOLE suite twice.
# At 160 s a run, the six refutations of plan-preflight.sh cost 32 minutes of wall clock to prove
# six lines of code.
#
# A case is a file. It sources this, builds its own fixtures, and exits non-zero if any assertion
# failed. The runner sums. Nothing crosses between cases -- measured before the split: eight
# variables did, and `ROADWORTHY_DATA` was exported in one section and still live six hundred
# lines later, which is environment leaking, not state sharing.
[ -n "${RW_TEST_LIB:-}" ] && return 0
RW_TEST_LIB=1
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export CLAUDE_PLUGIN_ROOT="$ROOT"

FAIL=0
# A TRAP THIS SUITE SET FOR ITSELF, measured 2026-09-13: with `set -o pipefail` above, a
# pipeline `<live command> | grep -q PATTERN` fails whenever the producer writes anything AFTER
# the match -- grep -q exits at once, the producer takes SIGPIPE (141), and pipefail turns that
# into a red assertion about something that actually worked. Adding one warning line to
# close.sh broke an unrelated FRESH assertion this way. Rule: capture the output into a
# variable first, then match it. Only match a live pipeline when the pattern is on its LAST
# line, where there is nothing left to write.
ok()   { printf '  [OK]   %s\n' "$1"; }
fail() { printf '  [FAIL] %s\n' "$1" >&2; FAIL=$((FAIL + 1)); }
section() { printf '\n== %s\n' "$1"; }

# run_hook <name> <json> → sets OUT (stdout), ERR (stderr), RC
# shellcheck disable=SC2034  # OUT, RC and ERR are this function's outputs, read by the cases.
run_hook() {
  local name="$1" json="$2"
  set +e
  OUT="$(printf '%s' "$json" | bash "$ROOT/hooks/run-hook.cmd" "$name" 2>"$TMP/err")"
  RC=$?
  set -e
  ERR="$(cat "$TMP/err")"
}
# A denial is judged by its SHAPE, not by a substring. `grep -q '"permissionDecision": "deny"'`
# accepted any line that merely contained those characters -- including output that is not JSON
# at all -- and rejected valid JSON formatted with different spacing. Both directions measured.
denied()  { printf '%s' "$OUT" | python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(1)
o = d.get("hookSpecificOutput") or {}
sys.exit(0 if o.get("permissionDecision") == "deny" else 1)'; }
# And once per guard, the WHOLE envelope is compared against the golden, key for key.
golden()  { printf '%s' "$OUT" | python3 "$ROOT/tests/goldens/check.py" "$ROOT/tests/goldens/$1" 2>"$TMP/golden.err"; }
# why() prints the divergence the golden found, for the assertions that expect one.
why()     { sed "s/^/          /" "$TMP/golden.err"; }
context() { printf '%s' "$OUT" | python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])'; }

# A CASE THAT DID NOT REACH THE END DID NOT PASS. Measured 2026-09-14, with reproducers:
#   * `trap 'rm -rf "$TMP"' EXIT` makes an aborted script exit 0 -- the handler's last
#     command is the `rm`, and its status becomes the script's. That is what tests/run.sh
#     shipped with in 0.6.0: any abort turned the whole gate green with half of it unrun.
#   * carrying `$?` out of the handler is NOT enough either. On an unbound-variable abort
#     under `set -u`, the EXIT trap sees `$?=0` (bash 3.2, macOS); on an ordinary `set -e`
#     failure it sees 1. So the status alone cannot tell a finished case from a dead one.
# The flag can: `rw_end` is the only thing that sets it, and it is the last line of every
# case. No flag, no pass -- whatever the shell decided the status was.
TMP="$(mktemp -d)"
rw_exit() {
  local rc=$?
  rm -rf "$TMP"
  if [ "${RW_CASE_FINISHED:-0}" != 1 ]; then
    printf '  [CASE DIED] %s stopped before its last assertion\n' "${RW_CASE:-this case}" >&2
    exit 1
  fi
  exit "$rc"
}
trap rw_exit EXIT
RW_CASE="${BASH_SOURCE[1]:-unknown}"
HOME_SANDBOX="$TMP/home"; mkdir -p "$HOME_SANDBOX/.claude/plans"

# The fixtures a case asks for by name, instead of building a toy repository inline for the
# fourteenth time. Sourced here so a case file is one `source ../lib.sh` away from all of them.
# shellcheck source=/dev/null  # the fixture set is a directory, by design: adding one is adding a file.
for _fx in "$ROOT"/tests/fixtures/*.sh; do [ -f "$_fx" ] && . "$_fx"; done
unset _fx

# rw_end — the last line of every case. The runner reads the exit status, not the output.
rw_end() {
  RW_CASE_FINISHED=1
  if [ "$FAIL" -ne 0 ]; then
    printf '  %d failure(s) in %s\n' "$FAIL" "${BASH_SOURCE[1]##*/}" >&2
    exit 1
  fi
  exit 0
}
