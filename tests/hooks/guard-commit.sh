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
# (From 0.7.0 a commit also answers to the front; these assertions are about the empty check, so
# the fixtures carry a front whose scope covers what they stage.)
mkdir -p "$G/.roadworthy"; printf '**\n' > "$G/.roadworthy/scope"
echo x > "$G/f"; git -C "$G" add f
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$G\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "staged change allowed" || fail "staged change denied"
CLAUDE_PLUGIN_OPTION_BLOCK_EMPTY_COMMITS=false run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"git commit -m m\"}}"
! denied && ok "block_empty_commits=false honoured" || fail "block_empty_commits=false"
G2="$TMP/git2"; mkdir -p "$G2"; git -C "$G2" init -q; git -C "$G2" config user.email t@t; git -C "$G2" config user.name t
run_hook guard-commit "{\"tool_name\":\"Bash\",\"cwd\":\"$TMP\",\"tool_input\":{\"command\":\"cd $G2 && git commit -m m\"}}"
denied && ok "leading cd: empty staging in the target repo denied" || fail "cd-prefixed commit judged by the wrong directory"
mkdir -p "$G2/.roadworthy"; printf '**\n' > "$G2/.roadworthy/scope"
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

# ── 0.7.0: what enters the history is what the front declared ────────────────
# The entry gate reads commands, and a program that opens a file itself writes through nothing a
# reader can name. The commit is where the set is exact: git's own index. However a file outside
# the scope was written, it does not reach the history.
section "guard-commit (the commit takes only what the front declared)"
CS="$TMP/commit-scope"; mkdir -p "$CS/src" "$CS/outside" "$CS/lib/auth" "$CS/docs/plans" "$CS/.roadworthy"
git -C "$CS" init -q; git -C "$CS" config user.email t@t; git -C "$CS" config user.name t
printf 'a\n' > "$CS/src/a.py"; printf 'b\n' > "$CS/outside/b.py"; printf 't\n' > "$CS/lib/auth/token.py"
git -C "$CS" add -A; git -C "$CS" commit -q -m base
gcs() { run_hook guard-commit "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$CS" "$1")"; }
printf 'src/**\n' > "$CS/.roadworthy/scope"
printf 'a2\n' > "$CS/src/a.py"; printf 'b2\n' > "$CS/outside/b.py"     # written by "any means"
gcs 'git add src && git commit -q -m inside'
! denied && ok "with a front open, a commit of what the scope covers passes" || fail "an in-scope commit was denied: $OUT"
for cmd in 'git add -A && git commit -q -m x' 'git commit -q -a -m x' 'git commit -qam x' 'git add outside/b.py; git commit -q -m x' \
           'git commit -q -m x -- outside/b.py' 'git add . && git commit -q -m x' "git -C $CS commit -q -a -m x" "cd $CS/src && git commit -q -a -m x"; do
  gcs "$cmd"
  denied && printf '%s' "$OUT" | grep -q 'outside/b.py' || fail "a file outside the scope reached the history: $cmd -> $OUT"
done
ok "add -A, -a, -am, a named add, a pathspec, add ., git -C and a cd: none takes a path outside the scope, and the path is named"
git -C "$CS" add outside/b.py
gcs 'git commit -q -m "already staged by somebody"'
denied && printf '%s' "$OUT" | grep -q 'git restore --staged' && ok "what was already staged is judged too, and the way out is said" || fail "a file outside the scope reached the history (already staged): $OUT"
git -C "$CS" restore --staged outside/b.py; git -C "$CS" checkout -q -- outside/b.py
# What is protected does not enter the history either, scope or no scope.
printf 'lib/auth/**\n' > "$CS/.roadworthy/protected"; printf '**\n' > "$CS/.roadworthy/scope"
printf 't2\n' > "$CS/lib/auth/token.py"
gcs 'git commit -q -a -m x'
denied && printf '%s' "$OUT" | grep -q 'protected path' && ok "a protected path does not enter the history, even inside the scope" || fail "a file outside the scope reached the history (a protected one): $OUT"
git -C "$CS" checkout -q -- lib/auth/token.py; rm -f "$CS/.roadworthy/protected"
# No front: only the rite's own artefacts commit.
rm -f "$CS/.roadworthy/scope"
printf 'a3\n' > "$CS/src/a.py"
gcs 'git commit -q -a -m x'
denied && printf '%s' "$OUT" | grep -q 'no front is open' && ok "with no front open, work does not enter the history" || fail "a file outside the scope reached the history (no front at all): $OUT"
git -C "$CS" checkout -q -- src/a.py
printf '{"plans":"docs/plans"}\n' > "$CS/.roadworthy/docs.json"; printf 'true\n' > "$CS/.roadworthy/gates"
printf '# p\n' > "$CS/docs/plans/2026-10-01-0900-p.md"
gcs 'git add -A && git commit -q -m "the plan and the gates"'
! denied && ok "the plan, the gates and the owner's files commit with no front: they are what opens one" || fail "the rite's own artefacts were denied a commit: $OUT"
printf 'notes/**\n' > "$CS/.roadworthy/free"; mkdir -p "$CS/notes"; printf 'n\n' > "$CS/notes/n.md"
gcs 'git add notes && git commit -q -m notes'
! denied && ok "and so does what the owner freed" || fail "a freed path was denied a commit: $OUT"
gcs 'git log --oneline | head -3; git status'
! denied && ok "a command that is not a commit is not judged" || fail "a read was judged as a commit: $OUT"
# ── 0.7.0: the night's own files (the simulated night of 2026-10-01) ─────────────────────────
# overnight-start.sh writes the diary in the decisions directory and overnight-close.sh leaves the
# hand-off in the plans directory -- docs/decisions and docs/plans when the project declares
# neither. With the commit judged against the scope, a night whose plan did not name the diary's
# directory could not commit its diary, so it could not end; and the hand-off, written after the
# closing, could not be committed at all in a project with no docs.json.
rm -f "$CS/.roadworthy/docs.json"; mkdir -p "$CS/docs/decisions"
printf 'src/**\n' > "$CS/.roadworthy/scope"
printf 'd\n' > "$CS/docs/decisions/2026-10-01-0300-overnight-topic.md"; printf 'o\n' > "$CS/docs/decisions/other.md"
gcs 'git add docs/decisions/2026-10-01-0300-overnight-topic.md && git commit -q -m "the diary of the night"'
! denied && ok "the diary of the night commits under a scope that does not name it: the night's own script wrote it" || fail "the night could not commit its own diary (a dead end): $OUT"
gcs 'git add docs/decisions && git commit -q -m x'
denied && printf '%s' "$OUT" | grep -q 'docs/decisions/other.md' && ok "and nothing else in that directory rides along" || fail "a file outside the scope reached the history (next to the night's diary): $OUT"
rm -f "$CS/.roadworthy/scope" "$CS/docs/decisions/other.md"
printf 'h\n' > "$CS/docs/plans/2026-10-01-0600-handoff-overnight-topic.md"
gcs 'git add docs/plans/2026-10-01-0600-handoff-overnight-topic.md && git commit -q -m "the hand-off of the night"'
! denied && ok "the hand-off the night leaves commits with no front and no docs.json: it is written after the closing" || fail "the hand-off of the night could not be committed (a dead end): $OUT"
printf 'x\n' > "$CS/docs/plans/another.md"
gcs 'git add docs/plans/another.md && git commit -q -m x'
denied && ok "another file there, in a project that declares no plans directory, still needs a front" || fail "a file outside the scope reached the history (docs/plans, with no docs.json): $OUT"
rm -f "$CS/docs/plans/another.md"

# ── 0.7.0: a commit larger than the guard could judge inside its time limit ──────────────────
# A hook that runs out of time does not deny: the commit goes ahead unjudged. The set was matched
# one path at a time, a python3 per path and per list; 2,200 paths with a protected list declared
# ran past the 60 s of hooks/hooks.json (cold review, 2026-10-01). One process judges it now.
BIG="$TMP/commit-big"; mkdir -p "$BIG/src/gen" "$BIG/.roadworthy"
git -C "$BIG" init -q; git -C "$BIG" config user.email t@t; git -C "$BIG" config user.name t
printf 'x\n' > "$BIG/f"; git -C "$BIG" add -A; git -C "$BIG" commit -q -m base
printf 'src/**\n' > "$BIG/.roadworthy/scope"; printf 'lib/auth/**\n' > "$BIG/.roadworthy/protected"; printf 'notes/**\n' > "$BIG/.roadworthy/free"
python3 -c 'import sys
for i in range(2200): open("%s/src/gen/f%d.txt" % (sys.argv[1], i), "w").write("x\n")' "$BIG"
printf 'b\n' > "$BIG/outside.txt"; git -C "$BIG" add -A
BIG_EVENT="$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":"git commit -q -m big"}}))' "$BIG")"
BIG_START=$SECONDS
OUT="$(printf '%s' "$BIG_EVENT" | perl -e 'alarm 45; exec @ARGV' bash "$ROOT/hooks/run-hook.cmd" guard-commit 2>/dev/null || true)"
BIG_TOOK=$((SECONDS - BIG_START))
denied && printf '%s' "$OUT" | grep -q 'outside.txt' \
  && ok "a commit of 2,200 paths is judged in ${BIG_TOOK}s, inside the hook's time limit, and the one path outside the scope is named" \
  || fail "the guard ran out of time on a large commit (${BIG_TOOK}s for 2,200 paths, killed at 45; hooks.json gives it 60): $(printf '%s' "$OUT" | cut -c1-200)"

CLAUDE_PLUGIN_OPTION_COMMIT_SCOPE=false gcs 'git add -A && git commit -q -m x'
! denied && ok "commit_scope=false honoured" || fail "commit_scope=false ignored"

rw_end
