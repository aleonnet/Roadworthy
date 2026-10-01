#!/usr/bin/env bash
# rite-gate
# Run alone: bash tests/hooks/rite-gate.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── rite-gate: the rite stops being optional ────────────────────────────────
section "rite-gate"
# Measured on this repository on 2026-09-13: 60 edits, 117 shell commands, ZERO rite invocations,
# with the plugin installed and active, and nothing noticed. This is the wall for that.
RG="$TMP/rite"; mkdir -p "$RG/.roadworthy" "$RG/src"; git -C "$RG" init -q
rg() { run_hook rite-gate "{\"tool_name\":\"$1\",\"cwd\":\"$RG\",\"tool_input\":$2}"; }

rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "no front: an edit is denied, naming the rite that opens one" || fail "edit passed with no front"
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
denied && ok "no front: a shell write is denied too (117 of 177 acts went this way)" || fail "shell write passed with no front"
rg Bash "{\"command\":\"grep -n '>' $RG/src/a.py\"}"
! denied && ok "a read with > inside quotes is not a write" || fail "quoted > read as a redirection"
rg Bash "{\"command\":\"echo \$(date) is fine\"}"
! denied && ok "a command substitution is not a redirection" || fail "command substitution read as a write"
for verb in "tee $RG/src/a.py" "cp /etc/hosts $RG/src/a.py" "mv /tmp/x $RG/src/a.py" "sed -i s/a/b/ $RG/src/a.py" "dd of=$RG/src/a.py"; do
  rg Bash "{\"command\":\"$verb\"}"
  denied || fail "write verb passed with no front: $verb"
done
ok "tee, cp, mv, sed -i and dd of= are writes too"
# An empty scope file used to satisfy every check while switching the lock off: one `touch` and
# both fences were gone at once.
: > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "an empty scope file does not open a front" || fail "an empty scope file opens a front"
printf '# only a comment\n\n' > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && ok "nor does one that declares only comments" || fail "a comment-only scope opens a front"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$RG\",\"tool_input\":{\"file_path\":\"$RG/src/a.py\"}}"
# The REASON has to name the malformed front. Asking only "did it deny?" passes with the check
# removed, because an empty glob list matches nothing and the lock denies for that instead --
# measured with a planted defect.
denied && printf '%s' "$OUT" | grep -q 'declares no glob' \
  && ok "and the lock calls it a malformed front instead of standing down" || fail "empty scope switched the lock off"
# With a real front, work proceeds.
printf 'src/**\n' > "$RG/.roadworthy/scope"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
! denied && ok "with a front open, the edit proceeds" || fail "open front still denied"
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
! denied && ok "and so does the shell write" || fail "open front denied a shell write"
# The foundation is written by scripts, with or without a front.
for f in scope gates plan.snapshot state evidence.jsonl denials.jsonl refutations.jsonl preflight.jsonl readings.jsonl; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  denied || fail "the foundation file $f is editable by hand"
done
ok "no foundation file is editable by hand, front or no front"
# The same door, through the shell. Guarding only the edit tools left the exact hole the roadmap
# recorded from the field -- appending a glob to .roadworthy/scope with a justification quoted
# from the chat -- open one `>>` away, and only while a front WAS open, which is when it matters.
printf 'src/**\n' > "$RG/.roadworthy/scope"
rg Bash "{\"command\":\"echo docs/** >> $RG/.roadworthy/scope\"}"
denied && ok "the scope cannot be widened through the shell either, front open or not" || fail "the shell widened the scope"
rg Bash "{\"command\":\"cp /dev/null $RG/.roadworthy/plan.snapshot\"}"
denied || fail "the shell rewrote the snapshot"
rg Bash "{\"command\":\"tee $RG/.roadworthy/evidence.jsonl\"}"
denied || fail "the shell rewrote the evidence ledger"
ok "nor can the snapshot or the evidence ledger"
# The owner's configuration is the owner's. `.roadworthy/protected` is what protect-paths reads and
# `.roadworthy/overnight-rules` is what the night freezes; both were exempt here as "human
# configuration", which let the agent delete a line from the list that guards against the agent
# (acceptance 7 of the 0.6.0 plan, reversed on 2026-09-14: a fence whose input the guarded party
# edits is not a fence). The owner edits them outside the agent, as with the principles file.
# Since 0.7.0 `free` and `docs.json` are the owner's too. docs.json was editable on the argument
# that it "unlocks nothing" -- but the `plans` directory it names is exempt from this gate and from
# the scope lock, so pointing it at `.` exempted the repository (field note, 2026-09-18).
rg Bash "{\"command\":\"echo x > $RG/.roadworthy/protected\"}"
denied && printf '%s' "$OUT" | grep -q 'the owner' && ok "the owner's protected list cannot be written through the shell, front open" || fail "the agent edited the owner configuration through the shell: $OUT"
rg Bash "{\"command\":\"sed -i '' -e s/a/b/ $RG/.roadworthy/overnight-rules\"}"
denied && ok "nor the night rules" || fail "the agent edited the owner configuration (overnight-rules) through the shell"
for f in protected overnight-rules; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  denied || fail "the agent edited the owner configuration with the edit tool: $f"
done
ok "the owner's two files are denied to the edit tool as well"
for f in docs.json free; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  denied && printf '%s' "$OUT" | grep -q 'the owner' || fail "the agent edited docs.json (or free) with the edit tool: $f"
  rg Bash "{\"command\":\"echo x > $RG/.roadworthy/$f\"}"
  denied && printf '%s' "$OUT" | grep -q 'the owner' || fail "the agent edited docs.json (or free) through the shell: $f"
done
ok "docs.json and the free list are the owner's too, through both doors"
# ── removing the foundation is writing it ────────────────────────────────────
# The command reader recognised writes and not removals, and `mv` looked at its destination only.
# The chain measured on 2026-09-14: open the front, write outside the scope through the shell (a
# declared limit), `rm .roadworthy/plan.snapshot`, close -- the closing skipped every check it
# measures against the snapshot and the front closed `passed`, with nothing STALE because the
# fingerprint excludes the snapshot. `rm .roadworthy/state` cleared a gaps_found the same way, and
# `rm .roadworthy/overnight` ended a night.
for cmd in "rm $RG/.roadworthy/plan.snapshot" "rm -f .roadworthy/plan.snapshot" "unlink $RG/.roadworthy/state" "rmdir $RG/.roadworthy/stop-latch" "git rm -q .roadworthy/gates" "rm -rf $RG/.roadworthy" "rm -rf .roadworthy/" "rm .roadworthy/overnight" "rm .roadworthy/protected"; do
  rg Bash "{\"command\":\"$cmd\"}"
  denied || fail "the shell removed the snapshot (or another foundation file) with: $cmd"
done
ok "rm, rm -rf, unlink, rmdir and git rm on the foundation, the night marker and the owner's files are denied, front open"
rg Bash "{\"command\":\"mv $RG/.roadworthy/plan.snapshot /tmp/x\"}"
denied && ok "mv with the snapshot as its SOURCE is denied" || fail "mv carried the snapshot away"
rg Bash "{\"command\":\"rm $RG/src/old.py && rm -rf $RG/build\"}"
! denied && ok "removing ordinary files inside the scope still passes" || fail "rm denied outside the foundation: $OUT"
# The plan is the artefact of the rite itself, and lives outside the project.
RGP="$TMP/riteplans"; mkdir -p "$RGP"
rm -f "$RG/.roadworthy/scope"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RGP" run_hook rite-gate "{\"tool_name\":\"Write\",\"cwd\":\"$RG\",\"tool_input\":{\"file_path\":\"$RGP/a-plan.md\"}}"
! denied && ok "the plan file is writable with no front: it is what opens one" || fail "the rite gate denied the plan itself"
# A front that ended badly blocks the next one; no state at all is a new project.
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
printf '%s' "$OUT" | grep -q 'no front is open' && ok "with no state recorded, the refusal is about the missing front, not about a past one" || fail "no-state case reported as a bad state"
# 0.7.0: the recorded state no longer denies a write by itself. That refusal never blocked a front
# the rite had opened and denied four honest writes in one day (field note, 2026-09-30); an
# unfinished front is refused where a front OPENS, by scope-write.sh, with the two ways out.
printf 'gaps_found\n' > "$RG/.roadworthy/state"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && printf '%s' "$OUT" | grep -q 'no front is open' && ok "a front that ended in gaps is not a second wall: the refusal is still the missing front" || fail "the recorded state still denies by itself: $OUT"
printf 'passed\n' > "$RG/.roadworthy/state"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
printf '%s' "$OUT" | grep -q 'no front is open' && ok "a front that passed does not block the next one" || fail "passed state blocked the next front"
rm -f "$RG/.roadworthy/state"
# Outside a git repository the gate is inert: it has no project to protect.
NOGIT="$TMP/nogit-rite"; mkdir -p "$NOGIT"
run_hook rite-gate "{\"tool_name\":\"Edit\",\"cwd\":\"$NOGIT\",\"tool_input\":{\"file_path\":\"$NOGIT/a.py\"}}"
! denied && ok "outside a git repository the gate is inert" || fail "the gate denied outside a repository"
# ── what the FIRST real session found, in its first two minutes ─────────────
# The gate had never run outside a synthetic event in a toy repository, and none of those events
# wrote outside the repository or carried `2>/dev/null`. All three below were measured on
# 2026-09-14, against the installed 0.6.0, with no front open.
rm -f "$RG/.roadworthy/scope" "$RG/.roadworthy/state"
rg Bash "{\"command\":\"echo x > $TMP/outside-the-repo.txt\"}"
! denied && ok "a shell write OUTSIDE the repository is not this repository's work" || fail "the gate denied a write outside the repository: $OUT"
# `2>/dev/null` was denied for the same reason, and is fixed by the same rule: /dev/null is not
# inside the repository. A list of device names was written here first and then removed -- the
# refutation proved it was dead code, because the outside-the-repository rule already answered it.
rg Bash "{\"command\":\"grep -n x $RG/src/a.py 2>/dev/null\"}"
! denied && ok "2>/dev/null is not a write (the commonest idiom in shell)" || fail "2>/dev/null denied: $OUT"
for dev in /dev/stdout /dev/stderr /dev/tty /dev/fd/2; do
  rg Bash "{\"command\":\"echo x > $dev\"}"
  denied && fail "a write to the device $dev was denied"
done
ok "nor is a write to /dev/stdout, /dev/stderr, /dev/tty or /dev/fd/2"
# And the one that made the gate unopenable: the plan is what OPENS a front, and through the shell
# it was denied -- so the first front of a project could only be opened with the edit tool.
# plans_dir INSIDE the repository is the only case where the exemption does any work: outside it,
# the rule about writes outside the repository already answers. A project that keeps its plans in
# docs/plans is exactly that case.
RGP2="$RG/docs/plans"; mkdir -p "$RGP2"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RGP2" run_hook rite-gate "{\"tool_name\":\"Bash\",\"cwd\":\"$RG\",\"tool_input\":{\"command\":\"cat > $RGP2/p.md\"}}"
! denied && ok "the plan can be written through the shell too, with no front" || fail "the shell could not write the plan that opens the front: $OUT"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RGP2" run_hook rite-gate "{\"tool_name\":\"Bash\",\"cwd\":\"$RG\",\"tool_input\":{\"command\":\"cat > $RG/docs/other.md\"}}"
denied && ok "and a neighbour of the plans directory is still denied" || fail "the plans exemption spilled onto its parent"
# The plan has TWO homes: plans_dir (where plan mode writes) and the `plans` directory the
# project declares in .roadworthy/docs.json (where the house norm keeps them). A plan written in
# the second was denied here with no front open -- the field case of 2026-09-08 -- so the second
# home is exempt like the first, through both doors, and nothing else under docs/ is.
mkdir -p "$RG/docs/plans"; printf '{"plans":"docs/plans"}\n' > "$RG/.roadworthy/docs.json"
rg Write "{\"file_path\":\"$RG/docs/plans/2026-01-01-0900-p.md\"}"
! denied && ok "a plan in the project's own plans directory (docs.json) can be written with no front" || fail "the rite is denied in the home the house norm uses: $OUT"
rg Bash "{\"command\":\"cat > $RG/docs/plans/2026-01-01-0900-p.md\"}"
! denied && ok "through the shell too" || fail "the shell could not write the plan in docs/plans: $OUT"
rg Write "{\"file_path\":\"$RG/docs/decisions/x.md\"}"
denied && ok "and the rest of docs/ is still denied with no front" || fail "the docs.json exemption spilled past the plans directory"
rm -f "$RG/.roadworthy/docs.json"
# None of that loosens what the gate is for.
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
denied && ok "a shell write INSIDE the repository is still denied with no front" || fail "the gate stopped guarding its own repository"
rg Bash "{\"command\":\"echo x > $RG/.roadworthy/scope 2>/dev/null\"}"
denied && printf '%s' "$OUT" | grep -q 'written by a script' \
  && ok "and the foundation is still denied even next to a device redirection" || fail "the device exemption leaked onto the foundation: $OUT"

# ── 0.7.0: the command is read the way the shell reads it ───────────────────
# The reader lived in this hook as forty lines that split on spaces. Sounded on 2026-09-30 with
# eight forms aimed at the foundation, six went through: a command on a second line, behind an
# assignment, behind `command`, inside `$( )`, inside `if ...; then`, and `sed -i.bak`. It also
# collected a verb's arguments to the end of the whole line, so `cp x .roadworthy/state && true`
# examined the word `true`. hooks/shellread.py is the reader now; its grammar is measured row by
# row in tests/scripts/shellread.sh, and here the hook is measured with it in place.
rgc() { run_hook rite-gate "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"tool_input":{"command":sys.argv[2]}}))' "$RG" "$1")"; }
printf 'src/**\n' > "$RG/.roadworthy/scope"       # a front is open: only the foundation can deny
for cmd in $'true\nrm .roadworthy/plan.snapshot' 'X=1 rm .roadworthy/plan.snapshot' 'command rm .roadworthy/plan.snapshot' \
           'echo $(rm .roadworthy/plan.snapshot)' 'if true; then rm .roadworthy/plan.snapshot; fi' \
           'sed -i.bak s/a/b/ .roadworthy/gates' 'bash -c "rm .roadworthy/plan.snapshot"' \
           'find .roadworthy -name plan.snapshot -delete' 'tar xzf a.tgz -C .roadworthy'; do
  rgc "$cmd"
  denied || fail "a write hid behind a form the reader did not follow: $cmd"
done
ok "a second line, an assignment, a wrapper, a substitution, if/then, sed -i.bak, bash -c, find -delete and tar -C no longer hide a write to the foundation"
rgc 'cp /dev/null .roadworthy/state && true'
denied && printf '%s' "$OUT" | grep -q "'.roadworthy/state' is written by a script" \
  && ok "a verb followed by another command is judged by ITS target, not by the last word of the line" || fail "the reader examined the wrong word: $OUT"
rgc 'sed -i s/a/b/ src/a.py && git status --short | wc -l'
! denied && ok "and an ordinary edit followed by a pipeline is not mistaken for a write to the last word" || fail "the reader examined the wrong word (an in-scope edit was denied): $OUT"
rm -f "$RG/.roadworthy/scope"                      # no front: any write inside the repository denies
rgc $'python3 - <<\'PY\'\nif o.get("ts", "") >= "2026-09-30T17": print(o)\nPY'
! denied && ok "a comparison inside the body of a heredoc is not a redirection (field, 2026-09-30 19:58)" || fail "a read was taken for a write (heredoc body): $OUT"
rgc 'grep -n "a\|'"'"'>'"'"'\|\">\"\|>>x" hooks/rite-gate'
! denied && ok "nor is a > after an escaped quote (field, 2026-09-30 20:09)" || fail "a read was taken for a write (escaped quote): $OUT"
rgc "cd $TMP && echo x > relative.txt"
! denied && ok "a relative path is relative to where the command went, not to where the session stands" || fail "a write after cd was judged at the session directory: $OUT"
rgc $'cd src\necho x > a.py'
denied && ok "and a relative write inside the repository, after a cd inside it, is still denied with no front" || fail "a cd hid a write inside the repository"

# ── 0.7.0: what the first cold review of the reader walked through ───────────
# A list of verbs that write never closes. For the rite's own directory the rule is the other way
# round: only a command known to read is handed a path there.
fx_put() { printf '%s\n' "$2" > "$1"; }             # fixtures are written here, never by the hook under test
fx_put "$RG/.roadworthy/scope" 'src/**'; fx_put "$RG/.roadworthy/plan.snapshot" '{}'; fx_put "$RG/.roadworthy/state" 'passed'
for cmd in 'gzip .roadworthy/state' 'chmod 000 .roadworthy/gates' 'shred -u .roadworthy/state' 'vim .roadworthy/scope' \
           '$tool .roadworthy/state' 'sort -o .roadworthy/gates README.md' 'cp README.md .roadworthy/' \
           'git checkout .roadworthy/gates' 'echo x 1<>.roadworthy/state' '[[ -n x ]] > .roadworthy/state' \
           'echo .roadworthy/plan.snapshot | xargs rm' 'rm .roadworth?/plan.snapshot' '{rm,.roadworthy/plan.snapshot}'; do
  rgc "$cmd"
  denied || fail "a write hid behind a command the reader has no verb for: $cmd"
done
ok "a path of the rite handed to anything not known to only read is denied (gzip, chmod, an editor, a glob, a brace)"
for cmd in 'cat .roadworthy/state' 'ls -la .roadworthy && head -3 .roadworthy/plan.snapshot' 'for f in .roadworthy/*; do wc -l "$f"; done' \
           'grep -c x .roadworthy/gates | tee /dev/null' 'git add .roadworthy/gates' '[ -f .roadworthy/scope ] && echo open' \
           'diff .roadworthy/state .roadworthy/gates' 'jq . .roadworthy/plan.snapshot'; do
  rgc "$cmd"
  ! denied || fail "a read was taken for a write (reading the rite's own files): $cmd -> $OUT"
done
ok "and reading the rite's files is reading: cat, ls, a loop of wc, grep, git add, test, diff, jq"
# What cannot be followed, in a command that names the rite's directory.
for cmd in 'd=/tmp; for d in .roadworthy; do rm $d/plan.snapshot; done' 'x=$(echo .roadworthy/state); rm $x' \
           'eval eval eval eval eval eval eval eval eval eval rm .roadworthy/plan.snapshot' 'find "$d" -name "*.snapshot" | xargs rm; ls .roadworthy'; do
  rgc "$cmd"
  denied && printf '%s' "$OUT" | grep -q 'could not be followed' || fail "a write hid behind a variable, a pipe or nesting the reader cannot follow: $cmd -> $OUT"
done
ok "a removal through a loop variable, a substitution, a pipe or ten evals is denied when the command names .roadworthy"
rgc 'rm "$stale"; echo done'
! denied && ok "and the same unknown target in a command that does not name it is ordinary work" || fail "an unknown variable alone was denied with a front open: $OUT"
# A directory the reader followed and the shell did not must not move the foundation out of sight.
for cmd in 'f() { cd /tmp; }; rm .roadworthy/plan.snapshot' 'false && cd /tmp; rm .roadworthy/plan.snapshot' \
           'cd /nonexistent-rw-dir; rm .roadworthy/plan.snapshot' 'cd /tmp & rm .roadworthy/plan.snapshot' \
           "eval 'cd .roadworthy'; rm plan.snapshot" 'cd .roadworthy && rm plan.snapshot'; do
  rgc "$cmd"
  denied || fail "a cd the shell never made hid the foundation: $cmd"
done
ok "a cd the reader followed and the shell did not does not hide the rite's directory: it is known by name"
# A removal that names no file is judged by what lies under what it sweeps.
rgc 'find . -delete'
denied && printf '%s' "$OUT" | grep -q 'names no file' && ok "find -delete over the repository is a removal of the foundation" || fail "a sweep reached the foundation: find . -delete -> $OUT"
rgc 'find . -name plan.snapshot | xargs rm'
denied && ok "so is find piped into xargs rm, when the names it selects are the rite's" || fail "a sweep reached the foundation: find | xargs rm"
rgc "rm -rf $RG"
denied && printf '%s' "$OUT" | grep -q 'names no file' && ok "and removing the directory that holds the rite's removes the rite's" || fail "a sweep reached the foundation: rm -rf of the repository itself -> $OUT"
rgc "find . -name '*.bak' -delete"
! denied && ok "and a find whose pattern cannot match the rite's files is ordinary work" || fail "an ordinary find -delete was denied: $OUT"
rgc 'find src -type f -delete'
! denied && ok "as is one that sweeps a directory the rite is not under" || fail "find under src was denied: $OUT"
# git takes what it does not track: exactly the rite's files that are neither tracked nor ignored.
rgc 'git clean -fd'
denied && printf '%s' "$OUT" | grep -q 'untracked and not ignored' && ok "git clean is denied while the rite's files are untracked and not ignored" || fail "a sweep reached the foundation: git clean -fd -> $OUT"
rgc 'git stash -u'
denied && ok "and so is git stash -u" || fail "a sweep reached the foundation: git stash -u"
fx_put "$RG/.gitignore" '.roadworthy/'
rgc 'git clean -fd'
! denied && ok "once the project ignores them, git clean does not reach them and is ordinary work" || fail "git clean was denied though git would not touch the rite's files: $OUT"
rgc 'git clean -fdx'
denied && ok "but -x takes what is ignored too" || fail "a sweep reached the foundation: git clean -fdx"
rgc 'git clean -fdx -- build'
! denied && ok "unless it names what it cleans" || fail "git clean on a named path was denied: $OUT"
rm -f "$RG/.gitignore"

# ── 0.7.0: what is protected is protected through the shell too ─────────────
fx_put "$RG/.roadworthy/protected" 'lib/auth/**'; fx_put "$RG/.roadworthy/scope" '**'
rgc 'sed -i.bak s/a/b/ lib/auth/token.py'
denied && printf '%s' "$OUT" | grep -q 'protected path' && ok "a protected path cannot be rewritten through the shell, front open and in scope" || fail "the shell wrote a protected path: $OUT"
rgc 'rm lib/auth/token.py'
denied && ok "nor removed" || fail "the shell wrote a protected path (removal)"
rgc 'cat lib/auth/token.py && echo x > lib/other.py'
! denied && ok "reading it, and writing next to it, is ordinary work" || fail "the protected list denied more than it names: $OUT"
CLAUDE_PLUGIN_OPTION_PROTECTED_PATHS='**/secrets.env' rgc 'echo K=1 >> config/secrets.env'
denied && ok "the user's own protected_paths option holds through the shell as well" || fail "the shell wrote a protected path (the option list)"
rm -f "$RG/.roadworthy/protected"

# ── 0.7.0: the front that counts is the one of the repository the target is in ──────────
OTH="$TMP/rite-other"; mkdir -p "$OTH/.roadworthy" "$OTH/lib"; git -C "$OTH" init -q
OTH="$(cd "$OTH" && pwd -P)"
fx_put "$RG/.roadworthy/scope" 'src/**'           # the session's repository has a front; the other has none
rg Edit "{\"file_path\":\"$OTH/lib/x.py\"}"
denied && printf '%s' "$OUT" | grep -q "no front is open in $OTH" && ok "an edit in ANOTHER repository answers to that repository: no front there, denied, naming it" || fail "the session repository decided for a file of another (edit passed or named the wrong one): $OUT"
rgc "echo x > $OTH/lib/x.py"
denied && printf '%s' "$OUT" | grep -q "no front is open in $OTH" && ok "through the shell too" || fail "the session repository decided for a file of another (shell): $OUT"
[ -f "$OTH/.roadworthy/denials.jsonl" ] && ok "and the refusal is recorded in the repository it is about" || fail "the denial about another repository was not recorded there"
rgc "echo x > $OTH/.roadworthy/scope"
denied && printf '%s' "$OUT" | grep -q 'written by a script' && ok "the foundation of another repository is a foundation" || fail "the session repository decided for a file of another (its foundation was writable): $OUT"
rm -f "$RG/.roadworthy/scope"; fx_put "$OTH/.roadworthy/scope" 'lib/**'   # now the other way round
rg Edit "{\"file_path\":\"$OTH/lib/x.py\"}"
! denied && ok "and with a front open THERE, the edit proceeds though the session's repository has none" || fail "the session repository decided for a file of another (denied by its own missing front): $OUT"
rgc "cd $OTH && echo x > lib/x.py"
! denied && ok "as does a shell write after a cd into it" || fail "a write in a repository with a front was denied from another: $OUT"
# The agent's own working places need no front, whatever is built in them.
SCR="$TMP/rite-scratch"; mkdir -p "$SCR/toy/.roadworthy"; git -C "$SCR/toy" init -q; SCR="$(cd "$SCR" && pwd -P)"
rgs() { run_hook rite-gate "$(python3 -c 'import json,sys; print(json.dumps({"tool_name":"Bash","cwd":sys.argv[1],"scratchpad_dir":sys.argv[3],"tool_input":{"command":sys.argv[2]}}))' "$RG" "$1" "$SCR")"; }
rgs "echo 'src/**' > $SCR/toy/.roadworthy/scope && echo x > $SCR/toy/a.py && rm -rf $SCR/toy/.roadworthy"
! denied && ok "a toy repository in the session scratchpad -- its own .roadworthy included -- is scratch" || fail "the scratchpad was gated: $OUT"
rgc "echo 'src/**' > $SCR/toy/.roadworthy/scope"
denied && ok "and the same path without that field is a foundation like any other (the check discriminates)" || fail "the scratchpad exemption does not depend on the field"
# What the owner declared outside the rite needs no front.
fx_put "$RG/.roadworthy/free" 'notes/**'
rgc 'echo x > notes/2026-09-30-field.md'
! denied && ok "a path under .roadworthy/free is written with no front" || fail "the owner's free list was ignored by the gate: $OUT"
rg Edit "{\"file_path\":\"$RG/notes/a.md\"}"
! denied && ok "with the edit tool too" || fail "the owner's free list was ignored by the edit door: $OUT"
rgc 'echo x > src/a.py'
denied && ok "and what is not on it still needs a front" || fail "the free list freed more than it names"
rm -f "$RG/.roadworthy/free"
# The plans exemption is for the plan, never for the directory.
mkdir -p "$RG/docs/plans/sub"; fx_put "$RG/.roadworthy/docs.json" '{"plans":"docs/plans"}'
for t in docs/plans/sub/x.md docs/plans/tool.sh; do
  rg Write "{\"file_path\":\"$RG/$t\"}"
  denied || fail "the plans exemption covered more than the plan: $t"
  rgc "echo x > $t"
  denied || fail "the plans exemption covered more than the plan (shell): $t"
done
ok "a subdirectory of the plans home, and a file there that is not a .md, are not the plan"
fx_put "$RG/.roadworthy/docs.json" '{"plans":"."}'
rg Write "{\"file_path\":\"$RG/README.md\"}"
denied && ok "and a plans home pointed at the repository root is not honoured" || fail "the plans exemption covered more than the plan: plans='.' exempted the root"
rm -f "$RG/.roadworthy/docs.json"

# ── 0.7.0: what the adversarial simulation and the hunt for dead ends found (2026-10-01) ─────
# A refusal never CREATES the plugin's directory in a repository that has none: the ledger it
# wrote there was an untracked file the agent may not remove, and inside a submodule that made the
# parent's front impossible to close.
BARE="$TMP/rite-bare"; mkdir -p "$BARE"; git -C "$BARE" init -q; BARE="$(cd "$BARE" && pwd -P)"
rg Edit "{\"file_path\":\"$BARE/a.py\"}"
denied && [ ! -e "$BARE/.roadworthy" ] && ok "a refusal in a repository with no .roadworthy leaves nothing behind" || fail "a refusal created the plugin directory in a repository that has none"
# A repository INSIDE another one, with no rite of its own, answers to the one that holds it.
fx_put "$RG/.roadworthy/scope" 'src/**'
mkdir -p "$RG/src/vendored"; git -C "$RG/src/vendored" init -q
rg Edit "{\"file_path\":\"$RG/src/vendored/x.py\"}"
! denied && ok "a nested repository with no rite of its own answers to the one that holds it: in its scope, allowed" || fail "a nested repository was asked for a front of its own: $OUT"
# On a case-insensitive disk -- the default on macOS -- `.Roadworthy/scope` IS the scope.
for cmd in 'echo x > .Roadworthy/scope' 'cp /dev/null .ROADWORTHY/state' 'vim .Roadworthy/gates' 'rm .RoadWorthy/plan.snapshot'; do
  rgc "$cmd"
  denied || fail "the rite's directory spelled in another case was not recognised: $cmd"
done
ok "the rite's directory is recognised whatever its case: a redirection, cp, an editor, rm"
rg Edit "{\"file_path\":\"$RG/.Roadworthy/scope\"}"
denied && ok "through the edit tools too" || fail "the rite's directory spelled in another case was not recognised (edit tool)"
# A hook that runs out of its time limit does not deny: the call goes ahead. A command naming
# more targets than the gate can judge in that time is refused whole.
MANY="$(python3 -c 'print("rm " + " ".join("src/gen/f%d.txt" % i for i in range(401)))')"
rgc "$MANY"
denied && printf '%s' "$OUT" | grep -q 'more than 400 separate targets' && ok "a command naming more than 400 targets is refused whole, and told to split" || fail "a command with more targets than the gate can judge was let through: $(printf '%s' "$OUT" | cut -c1-120)"

CLAUDE_PLUGIN_OPTION_RITE_GATE=false rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
! denied && ok "rite_gate=false honoured" || fail "rite_gate=false ignored"

rw_end
