#!/usr/bin/env bash
# guard-commit
# Run alone: bash tests/hooks/guard-commit.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── guard-commit ─────────────────────────────────────────────────────────────
section "guard-commit"
G="$TMP/git"; mkdir -p "$G"; git -C "$G" init -q; git -C "$G" config user.email t@t; git -C "$G" config user.name t
TR='--tr'; TR="${TR}ailer"
# The REASON has to name the flag. Asking only "did it deny?" passes with the flag check broken,
# because the empty-staging check denies the same command for its own reason -- measured with a
# planted defect, which is the whole point of refuting an assertion before trusting it.
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit $TR x -m m\"}}"
denied && printf '%s' "$OUT" | grep -q 'is forbidden in commits' \
  && ok "forbidden flag denied, and the reason names the flag" || fail "forbidden flag passed"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
denied && ok "empty staging denied" || fail "empty staging passed"
echo x > "$G/f"; git -C "$G" add f
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "staged change allowed" || fail "staged change denied"
CLAUDE_PLUGIN_OPTION_BLOCK_EMPTY_COMMITS=false run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "block_empty_commits=false honoured" || fail "block_empty_commits=false"
G2="$TMP/git2"; mkdir -p "$G2"; git -C "$G2" init -q; git -C "$G2" config user.email t@t; git -C "$G2" config user.name t
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"cd $G2 && git commit -m m\"}}"
denied && ok "leading cd: empty staging in the target repo denied" || fail "cd-prefixed commit judged by the wrong directory"
echo y > "$G2/g"; git -C "$G2" add g
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"cd $G2 && git commit -m m\"}}"
! denied && ok "leading cd: staged change in the target repo allowed" || fail "cd-prefixed commit with staging denied"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git -C $G2 commit -m m\"}}"
! denied && ok "git -C: judged by the named repo" || fail "git -C judged by cwd"
git -C "$G2" commit -q -m g
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G2\",\"tool_input\":{\"command\":\"git add -A && git commit -m m\"}}"
! denied && ok "staging on the same line is left to git" || fail "add && commit denied before the add ran"
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"echo hello\"}}"
! denied && [ "$RC" -eq 0 ] && ok "non-commit command untouched" || fail "non-commit denied"

rw_end
