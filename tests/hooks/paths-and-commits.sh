#!/usr/bin/env bash
# paths-and-commits
# Run alone: bash tests/hooks/paths-and-commits.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── what the attack suite found ─────────────────────────────────────────────
# Two defects that the direct assertions never asked about, because they asked whether each fence
# denies what it says and not whether there is a way around it.
section "paths that do not exist yet, and commits written with -C"
RP="$TMP/rp"; mkdir -p "$RP/.roadworthy" "$RP/src"; git -C "$RP" init -q
# `.roadworthy/stop-latch/` is created lazily by stop-gate, so NOT existing is its normal state.
# Resolving only the dirname left such a path unresolved (/var vs /private/var on macOS), it landed
# outside the resolved root, matched no foundation entry, and the latch was writable by hand
# exactly when it mattered.
run_hook rite-gate "{\"tool_name\":\"Bash\",\"cwd\":\"$RP\",\"tool_input\":{\"command\":\"echo x > $RP/.roadworthy/stop-latch/s1\"}}"
denied && printf '%s' "$OUT" | grep -q 'stop-latch' \
  && ok "a file inside a foundation directory that does not exist yet is still denied" \
  || fail "the stop latch was writable by hand: $OUT"
# The negative control needs a front OPEN, or the refusal is about the missing front and the
# assertion measures nothing -- which is how it was written first, and it passed for the wrong
# reason until the suite said so.
printf '**\n' > "$RP/.roadworthy/scope"
run_hook rite-gate "{\"tool_name\":\"Bash\",\"cwd\":\"$RP\",\"tool_input\":{\"command\":\"echo x > $RP/src/deep/er/state.txt\"}}"
! denied && ok "and a deep path that is not foundation is not mistaken for one" || fail "a normal deep path was denied: $OUT"
run_hook rite-gate "{\"tool_name\":\"Bash\",\"cwd\":\"$RP\",\"tool_input\":{\"command\":\"echo x > $RP/.roadworthy/stop-latch/s2\"}}"
denied && ok "with the front open the latch is still denied" || fail "an open front unlocked the latch"
# The empty-staging trigger demanded `git` and `commit` adjacent, so `git -C <dir> commit` never
# reached it -- and the `-C` handling written for 0.3.0 twelve lines below it was unreachable code.
EC="$TMP/emptyc"; mkdir -p "$EC"; git -C "$EC" init -q
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$EC\",\"tool_input\":{\"command\":\"git commit -m x\"}}"
denied && ok "an empty commit is denied" || fail "empty commit passed"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git -C $EC commit -m x\"}}"
denied && printf '%s' "$OUT" | grep -q 'nothing is staged' \
  && ok "and so is the same commit written with git -C" || fail "git -C slipped past the empty check: $OUT"
git -C "$EC" config user.email t@t; git -C "$EC" config user.name t
printf 'x\n' > "$EC/f.txt"; git -C "$EC" add f.txt
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git -C $EC commit -m x\"}}"
! denied && ok "with something staged, the same -C commit passes" || fail "a real -C commit was denied: $OUT"

rw_end
