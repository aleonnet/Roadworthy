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
rg Bash "{\"command\":\"echo x > $RG/.roadworthy/protected\"}"
! denied && ok "and human configuration is still writable through the shell" || fail "the shell was denied human configuration"
for f in docs.json protected overnight-rules; do
  rg Edit "{\"file_path\":\"$RG/.roadworthy/$f\"}"
  ! denied || fail "human configuration $f denied by the rite gate"
done
ok "human configuration of the project stays editable"
# The plan is the artefact of the rite itself, and lives outside the project.
RGP="$TMP/riteplans"; mkdir -p "$RGP"
rm -f "$RG/.roadworthy/scope"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$RGP" run_hook rite-gate "{\"tool_name\":\"Write\",\"cwd\":\"$RG\",\"tool_input\":{\"file_path\":\"$RGP/a-plan.md\"}}"
! denied && ok "the plan file is writable with no front: it is what opens one" || fail "the rite gate denied the plan itself"
# A front that ended badly blocks the next one; no state at all is a new project.
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
printf '%s' "$OUT" | grep -q 'no front is open' && ok "with no state recorded, the refusal is about the missing front, not about a past one" || fail "no-state case reported as a bad state"
printf 'gaps_found\n' > "$RG/.roadworthy/state"
rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
denied && printf '%s' "$OUT" | grep -q 'ended as' && ok "a front that ended in gaps blocks the next one, and says so" || fail "gaps_found did not block: $OUT"
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
# None of that loosens what the gate is for.
rg Bash "{\"command\":\"echo x > $RG/src/a.py\"}"
denied && ok "a shell write INSIDE the repository is still denied with no front" || fail "the gate stopped guarding its own repository"
rg Bash "{\"command\":\"echo x > $RG/.roadworthy/scope 2>/dev/null\"}"
denied && printf '%s' "$OUT" | grep -q 'written by a script' \
  && ok "and the foundation is still denied even next to a device redirection" || fail "the device exemption leaked onto the foundation: $OUT"

CLAUDE_PLUGIN_OPTION_RITE_GATE=false rg Edit "{\"file_path\":\"$RG/src/a.py\"}"
! denied && ok "rite_gate=false honoured" || fail "rite_gate=false ignored"

rw_end
