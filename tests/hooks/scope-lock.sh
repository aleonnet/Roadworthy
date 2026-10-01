#!/usr/bin/env bash
# scope-lock
# Run alone: bash tests/hooks/scope-lock.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── scope-lock ───────────────────────────────────────────────────────────────
section "scope-lock"
REPO="$TMP/repo"; mkdir -p "$REPO/.roadworthy" "$REPO/src" "$REPO/docs" "$REPO/src/deep"
git -C "$REPO" init -q
printf '# scope\nsrc/**\n' > "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "edit outside scope denied" || fail "outside scope not denied"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/src/a.dart\"}}"
! denied && ok "edit inside scope allowed" || fail "inside scope denied"
# The foundation of the front is NOT editable by hand: exempting the whole .roadworthy/
# directory put the scope, the gates and the ledgers inside the blind spot of the guard that
# exists to protect them. Human configuration of the project stays editable, by name.
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/.roadworthy/scope\"}}"
denied && ok "the scope file itself is NOT editable by hand" || fail "scope file still editable"
# Nothing under .roadworthy/ is exempt here. `protected`, `overnight-rules`, `free` and -- since
# 0.7.0 -- `docs.json` are the owner's, denied by the rite gate through both doors; an exemption
# for any of them here would be dead code that reads as a promise. docs.json was exempt until
# then, and it declares the directory whose files the lock lets through: pointing `plans` at `.`
# exempted the whole repository (field note, 2026-09-18).
for cfg in protected overnight-rules free docs.json; do
  run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/.roadworthy/$cfg\"}}"
  denied || fail "the lock still exempts the owner's file $cfg (dead exemption)"
done
ok "the owner's files are not exempt here: the rite gate is the one door that says no, and this one does not contradict it"
# The scope belongs to the project, so the lock has to hold from a subdirectory too. Read at
# the session cwd it was simply absent one level down, and every edit passed.
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO/src/deep\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "the lock holds from a subdirectory of the project" || fail "lock inert from a subdirectory"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO/src/deep\",\"tool_input\":{\"file_path\":\"$REPO/src/a.dart\"}}"
! denied && ok "and still allows what is inside the scope from there" || fail "in-scope edit denied from a subdirectory"
# The plan lives outside the project, in the plans directory: the lock must not deny the rite's
# own artefact. Measured in the field on 2026-09-08 and again on 2026-09-13, in two projects:
# denied there, the agent's only way out was widening the scope by hand.
PLANS_SB="$TMP/plansdir"; mkdir -p "$PLANS_SB/sub"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PLANS_SB" run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$PLANS_SB/my-plan.md\"}}"
! denied && ok "the plan file (plans_dir) is editable while the lock is on" || fail "plan file denied by the scope lock"
# A file in no repository still answers to the session's front: the plan certainly did not
# declare it, and editing something in the home directory is collateral damage to nobody's plan.
# (The path does not exist and is not under a temporary directory, which is its own case below.)
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PLANS_SB" run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"/nonexistent-roadworthy-home/elsewhere.md\"}}"
denied && ok "a path outside every repository, and not temporary, is still denied by the session's scope" || fail "outside path passed"
# The plan's second home, the `plans` directory of .roadworthy/docs.json, is exempt the same way.
mkdir -p "$REPO/docs/plans"; printf '{"plans":"docs/plans"}\n' > "$REPO/.roadworthy/docs.json"
run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/plans/2026-01-01-0900-p.md\"}}"
! denied && ok "a plan in the project's declared plans directory is editable while the lock is on" || fail "the lock denied the plan in docs/plans: $OUT"
run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
denied && ok "and its parent is still outside the scope" || fail "the docs.json exemption spilled past the plans directory"
# The exemption is for the PLAN, never for the directory: until 0.7.0 anything under the plans
# directory, at any depth and of any kind, was editable under the lock.
mkdir -p "$REPO/docs/plans/done"
for p in docs/plans/done/old.md docs/plans/tool.sh docs/plans/sub/dir/x.md; do
  run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/$p\"}}"
  denied || fail "the plans exemption covered more than the plan: $p"
done
ok "a subdirectory of the plans home, and a file there that is not a .md, are not the plan"
# A home that IS the repository would exempt the repository.
printf '{"plans":"."}\n' > "$REPO/.roadworthy/docs.json"
run_hook scope-lock "{\"tool_name\":\"Write\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/README.md\"}}"
denied && ok "a plans home pointed at the repository root is not honoured" || fail "the plans exemption covered more than the plan: plans='.' exempted the root"
rm -f "$REPO/.roadworthy/docs.json"

# ── 0.7.0: the scope that judges a file is the one of the repository the file is in ─────────
# Resolved from the session's directory, the lock was wrong in both directions (field, 2026-09-18
# and 2026-09-22): a file of another repository was judged by a scope that knew nothing about it,
# and a temporary file in no repository was denied by a scope that had nothing to say about it.
OTHER="$TMP/other-repo"; mkdir -p "$OTHER/.roadworthy" "$OTHER/lib"; git -C "$OTHER" init -q
printf 'lib/**\n' > "$OTHER/.roadworthy/scope"
sl() { run_hook scope-lock "{\"tool_name\":\"Edit\",\"session_id\":\"x\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$1\"}${2:-}}"; }
sl "$OTHER/lib/x.py"
! denied && ok "a file of another repository is judged by THAT repository's scope: inside it, allowed" || fail "the session repository decided for a file of another (denied what its own scope allows): $OUT"
sl "$OTHER/src/a.dart"
denied && printf '%s' "$OUT" | grep -q "$OTHER/.roadworthy/scope" && ok "outside it, denied -- naming the other repository's scope" || fail "the session repository decided for a file of another (src/** is the session's glob, not this repository's): $OUT"
NOSCOPE="$TMP/noscope-repo"; mkdir -p "$NOSCOPE"; git -C "$NOSCOPE" init -q
sl "$NOSCOPE/a.py"
! denied && ok "a repository with no scope has no lock: that is the entry gate's question, not this one's" || fail "the session's scope locked another repository: $OUT"
sl "$TMP/notes-of-the-session.txt"
! denied && ok "a temporary file in no repository is nobody's project (35 such denials in one session, field 2026-09-22)" || fail "a file outside every repository was denied by the scope: $OUT"
# The agent's own working places: the session scratchpad (a documented field of every event) and
# the project memory next to the transcript -- even when a toy repository sits in the scratchpad.
SCR="$TMP/scratchpad"; mkdir -p "$SCR/toy/.roadworthy"; git -C "$SCR/toy" init -q; printf 'only/**\n' > "$SCR/toy/.roadworthy/scope"
sl "$SCR/toy/anything.py" ",\"scratchpad_dir\":\"$SCR\""
! denied && ok "a toy repository inside the session scratchpad is scratch, whatever scope it carries" || fail "the scratchpad was locked: $OUT"
sl "$SCR/toy/anything.py"
denied && ok "and without that field the same toy repository is judged like any other (the check discriminates)" || fail "the scratchpad exemption does not depend on the field"
MEMP="$HOME_SANDBOX/.claude/projects/-p"; mkdir -p "$MEMP/memory"
sl "$MEMP/memory/note.md" ",\"transcript_path\":\"$MEMP/s.jsonl\""
! denied && ok "the project memory next to the transcript is the agent's own, never a scope's" || fail "a memory note was denied by the scope: $OUT"
# What the owner declares outside the rite needs no scope.
printf '# the owner\nnotes/**\n' > "$REPO/.roadworthy/free"
sl "$REPO/notes/2026-09-30-a-field-note.md"
! denied && ok "a path under .roadworthy/free is outside the rite: no scope needed" || fail "the owner's free list was ignored: $OUT"
sl "$REPO/docs/readme.md"
denied && ok "and what is not on that list is still locked" || fail "the free list unlocked more than it names"
rm -f "$REPO/.roadworthy/free"
rm "$REPO/.roadworthy/scope"
run_hook scope-lock "{\"tool_name\":\"Edit\",\"cwd\":\"$REPO\",\"tool_input\":{\"file_path\":\"$REPO/docs/readme.md\"}}"
! denied && ok "no scope file → lock inactive" || fail "lock active without scope file"

rw_end
