#!/usr/bin/env bash
# plan-review-gate
# Run alone: bash tests/hooks/plan-review-gate.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── plan-review-gate ─────────────────────────────────────────────────────────
section "plan-review-gate"
# These three sections measure the REVIEW path. It is no longer the default (plan_gate is born
# in preflight), so they declare it; a section that does not would be exercising a branch the
# gate never reaches and reporting green for it.
export CLAUDE_PLUGIN_OPTION_PLAN_GATE=review
P="$HOME_SANDBOX/.claude/plans"; printf '# plan\n\n## Goal\n' > "$P/my-plan.md"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "no review → denied" || fail "no review passed"
printf 'plan: my-plan.md\nround: 1\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "approved review by name → allowed" || fail "approved review denied"
printf '# plan edited\n\n## Goal\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "editing the plan keeps the approval (what the user approved is what counts, no hash)" || fail "edit voided the approval"
printf 'plan: my-plan.md\nround: 2\nVERDICT: REJECTED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
# The reason has to name the rejection. Asking only "did it deny?" passes with the REJECTED
# branch removed, because the verdict then falls through to "has no verdict" and denies anyway
# -- measured with a planted defect.
denied && printf '%s' "$OUT" | grep -q 'rejected the plan' \
  && ok "rejected review → denied, and the reason says it was rejected" || fail "rejected review passed"
printf 'plan: my-plan.md\nround: 3\nVERDICT: ESCALATE\n## Recomendações\n- x\n## Alternativas\n- y — fonte: RFC 0000\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "escalated" && ok "ESCALATE → denied until the user answers" || fail "ESCALATE passed"
printf 'plan: my-plan.md\nround: 3\nVERDICT: ESCALATE\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "malformed" && ok "ESCALATE without recommendations/alternatives/sources is named malformed" || fail "malformed escalation not named"
printf 'plan: my-plan.md\nround: 3\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "ceiling" && ok "round 3 approved without the owner → denied (ceiling of 2)" || fail "round 3 passed without owner"
printf 'plan: my-plan.md\nround: 3\nowner: keep the plan, drop item 4\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "round 3 with the owner's decision → allowed" || fail "owner decision not honoured"
printf 'plan: my-plan.md\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' > "$P/my-plan.review.md"
printf '# plan\n\n## Goal\n\n## Overnight policy\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && printf '%s' "$OUT" | grep -q "grew" && ok "a section added after round 1 → denied (growth guard)" || fail "growth guard silent"
printf '# plan\n\n## Goal\n' > "$P/my-plan.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "same sections as round 1 → allowed" || fail "growth guard false positive"
printf '# other plan\n' > "$P/other.md"; sleep 1; touch "$P/other.md"   # newest by mtime, no review
run_hook plan-review-gate "$(python3 -c 'import json; print(json.dumps({"tool_name":"ExitPlanMode","tool_input":{"plan":"# plan\n\n## Goal"}}))')"
! denied && ok "the submitted plan (by content) wins over the newest file in the shared directory" || fail "newest file chosen over the submitted plan"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "without submitted text the newest file is the plan (other.md, unreviewed → denied)" || fail "fallback to newest broken"
rm "$P/other.md"
printf 'plan: ../x.md\nVERDICT: APPROVED\n' > "$P/evil.review.md"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "review with '/' in plan name refused" || fail "path traversal accepted"
rm "$P/evil.review.md"
CLAUDE_PLUGIN_OPTION_PLAN_REVIEW_REQUIRED=false run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "plan_review_required=false honoured" || fail "plan_review_required=false"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── plan-review-gate: the review inside the plan, and the project binding ────
section "plan-review-gate (plan mode writes one file)"
PB="$TMP/planbind"; RA="$TMP/repoA"; RB="$TMP/repoB"; mkdir -p "$PB" "$RA" "$RB"
git -C "$RA" init -q; git -C "$RB" init -q
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PB"
ev() { printf '{"tool_name":"ExitPlanMode","cwd":"%s","tool_input":{}}' "$1"; }
# Plan mode lets the agent write ONE file. Requiring the review as a second file made the rite
# impossible there (measured 2026-09-13: a ten-minute review with twelve blockers could not be
# written down at all), so the review may live in a '## Review' section of the plan itself.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 1\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "review in a '## Review' section of the plan → allowed" || fail "in-plan review denied: $OUT"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 1\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && ok "in-plan review without a verdict → denied" || fail "verdict-less in-plan review passed"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
printf 'plan: a.md\nVERDICT: REJECTED\n' > "$PB/a.review.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && ok "the sidecar review takes precedence over the in-plan section" || fail "sidecar ignored"
rm "$PB/a.review.md"
# The plans directory is shared by every project: 101 plans of several projects in one
# directory on the machine where this was measured, and the gate elected another project's.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
sleep 1; printf '# other\nproject: %s\n\n## Goal\n' "$RB" > "$PB/b.md"   # newer, another project, unreviewed
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a newer plan of another project does not win over this project's" || fail "cross-project plan elected"
run_hook plan-review-gate "$(ev "$RB")"
denied && printf '%s' "$OUT" | grep -q 'b.md' && ok "from the other repository its own plan is elected" || fail "project binding ignores the caller"
mkdir -p "$TMP/onlyother"; printf '# other\nproject: %s\n\n## Goal\n' "$RB" > "$TMP/onlyother/b.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/onlyother" run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'belongs to another project' && ok "another project's plan is named, not asked for a review" || fail "cryptic denial for another project's plan"
# One directory, two names: /var is a link to /private/var on macOS, so a declared path and a
# `git rev-parse` root differ as strings. Both sides are resolved before comparing.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$(cd "$RA" && pwd -P)" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a project declared through a resolved path still matches" || fail "symlinked project path treated as another project"
# The in-plan review's own heading is not growth.
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "the review's own heading does not trip the growth guard" || fail "in-plan review counted as growth"
printf '# plan\nproject: %s\n\n## Goal\n\n## New\n\n## Review\nround: 2\nsections-round1: Goal\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'grew' && ok "a real new section still denies" || fail "growth guard broken"
# A superseded plan is not a candidate: that is how the documentation norm retires one, and the
# gate reads the same vocabulary docs-check.sh reads (.roadworthy/docs.json, "status").
printf '# plan\nproject: %s\nstatus: superseded by b.md\n\n## Goal\n' "$RA" > "$PB/a.md"
printf '# plan\nproject: %s\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/b.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "a plan marked superseded is not elected" || fail "superseded plan elected: $OUT"
mkdir -p "$RA/.roadworthy"; printf '{"status":{"superseded by":"superado por"}}' > "$RA/.roadworthy/docs.json"
printf '# plan\nproject: %s\nstatus: superado por b.md\n\n## Goal\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "the project's own word for superseded is recognised" || fail "project status vocabulary ignored: $OUT"
# Two live plans of one project and nothing to tell them apart: refuse naming both. Electing the
# newest by date submitted a stale draft in the field (2026-09-13).
printf '# plan\nproject: %s\n\n## Goal\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'a.md, b.md' && ok "two live plans of one project → denied, both named" || fail "ambiguous plans not refused: $OUT"
# A directory of undeclared legacy drafts is NOT judged that way: it would block every user on
# upgrade. The old fallback still elects the newest.
mkdir -p "$TMP/legacy"; printf '# one\n' > "$TMP/legacy/one.md"; printf '# two\n' > "$TMP/legacy/two.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$TMP/legacy" run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'no review for the current plan' && ok "undeclared drafts are not blocked as ambiguous" || fail "legacy drafts refused as ambiguous: $OUT"
# A front written against a tag, with the tree ahead of it: plan and review must name the same
# base, and the base must resolve.
(cd "$RA" && git -c user.email=t@t -c user.name=t commit -q --allow-empty -m base && git tag v0)
printf '# plan\nproject: %s\nstatus: superado por a.md\n\n## Goal\n' "$RA" > "$PB/b.md"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nbase: v0\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
! denied && ok "plan and review declaring the same base → allowed" || fail "same base denied: $OUT"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'the working tree' && ok "a review with no base, on a plan that declares one → denied" || fail "baseless review passed: $OUT"
printf '# plan\nproject: %s\nbase: v0\n\n## Goal\n\n## Review\nbase: HEAD\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q "declares base 'v0'" && ok "a review made against another base → denied" || fail "wrong base passed: $OUT"
printf '# plan\nproject: %s\nbase: v-nope\n\n## Goal\n\n## Review\nbase: v-nope\nVERDICT: APPROVED\n' "$RA" > "$PB/a.md"
run_hook plan-review-gate "$(ev "$RA")"
denied && printf '%s' "$OUT" | grep -q 'does not resolve' && ok "a base that does not resolve → denied, naming the ref" || fail "unresolvable base passed: $OUT"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── refute.sh (refuted with a toy check) ─────────────────────────────────────
unset CLAUDE_PLUGIN_OPTION_PLAN_GATE

# ── plan-review-gate: review_suffix and Portuguese fields ───────────────────
section "plan-review-gate (review_suffix)"
export CLAUDE_PLUGIN_OPTION_PLAN_GATE=review
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$P"
printf '# plano\n' > "$P/outro.md"; sha="$(shasum -a 256 "$P/outro.md" | cut -d' ' -f1)"
printf 'plano: outro.md\nplano-sha256: %s\nVEREDITO: APROVADO\n' "$sha" > "$P/outro.banca.md"
CLAUDE_PLUGIN_OPTION_REVIEW_SUFFIX=.banca.md run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
! denied && ok "custom suffix + Portuguese fields accepted" || fail "custom suffix rejected: $OUT"
run_hook plan-review-gate '{"tool_name":"ExitPlanMode","tool_input":{}}'
denied && ok "default suffix ignores the .banca.md review" || fail "default suffix accepted wrong file"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

# ── docs-init: idempotent tree by role ──────────────────────────────────────
unset CLAUDE_PLUGIN_OPTION_PLAN_GATE

# ── plan-review-gate: the pre-flight is the criterion ────────────────────────
# The inversion of 0.6.0. The reviewer goes back to the diff (principle 4 of this plugin always
# said diff), and what guards the PLAN is the mechanical check. These assertions measure that the
# mode changes the CRITERION and never the on/off switch: an option that silently disabled the
# gate is exactly how a fence dies unnoticed.
section "plan-review-gate (plan_gate=preflight)"
PG="$TMP/pg"; PGP="$PG/plans"; PGR="$PG/repo"; mkdir -p "$PGP" "$PGR"
(
  cd "$PGR" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  printf 'one\ntwo\n' > src.txt
  git add -A; git commit -qm base
) >/dev/null 2>&1
PGR_REAL="$(cd "$PGR" && pwd -P)"
cat > "$PGP/good.md" <<PLANEOF
# A plan

project: $PGR_REAL

## Scope

\`\`\`
src.txt
\`\`\`

## Acceptance

| # | WHEN | THE SYSTEM SHALL |
|---|---|---|
| 1 | a | b |
PLANEOF
python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"cat src.txt"}}]}}))' > "$PG/t.jsonl"
export CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PGP"
PG_EVENT="{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"cwd\":\"$PGR\",\"transcript_path\":\"$PG/t.jsonl\"}"

run_hook plan-review-gate "$PG_EVENT"
! denied && ok "in preflight mode a green plan passes with NO review at all" || fail "green plan denied: $OUT"

# The whole point: the criterion changed, the switch did not.
sed -i.bak 's/^| 1 | a | b |$/| 3 | a | b |/' "$PGP/good.md"; rm -f "$PGP/good.md.bak"
run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q 'pre-flight is red' \
  && ok "a red pre-flight denies the submission" || fail "red pre-flight submitted: $OUT"
printf '%s' "$OUT" | grep -q 'acceptance numbers are not' \
  && ok "the denial carries what the pre-flight found" || fail "denial without the finding: $OUT"
sed -i.bak 's/^| 3 | a | b |$/| 1 | a | b |/' "$PGP/good.md"; rm -f "$PGP/good.md.bak"

# A plan whose scope was never read whole is the case this front exists for.
run_hook plan-review-gate "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"cwd\":\"$PGR\",\"transcript_path\":\"$PG/empty.jsonl\"}"
denied && printf '%s' "$OUT" | grep -q 'no transcript given' \
  && ok "without a transcript the gate refuses to take the plan's word" || fail "no-transcript submitted: $OUT"

# The boolean switch is untouched by the new option: off is off, in every mode.
CLAUDE_PLUGIN_OPTION_PLAN_REVIEW_REQUIRED=false run_hook plan-review-gate "$PG_EVENT"
! denied && [ "$RC" -eq 0 ] && ok "plan_review_required=false still silences the gate in preflight mode" \
  || fail "the boolean switch stopped working: $OUT"

# A mode nobody declared must not be guessed at.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=sometimes run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q "plan_gate is 'sometimes'" \
  && ok "an unknown plan_gate value denies, naming it" || fail "unknown mode tolerated: $OUT"

# In review mode the pre-flight is not consulted at all: the old path stays exactly as it was.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=review run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q 'no review for the current plan' \
  && ok "review mode still demands the reviewer, and only the reviewer" || fail "review mode changed: $OUT"

# And in both modes together, a green pre-flight is not enough on its own.
CLAUDE_PLUGIN_OPTION_PLAN_GATE=both run_hook plan-review-gate "$PG_EVENT"
denied && ok "both: a green pre-flight does not replace the verdict" || fail "both mode passed without a review: $OUT"

# ── the election: the transcript before the date, and the date said out loud ─
# Acceptance 16 and 17 of the 0.6.0 plan, promised by an accepted decision record and never built
# (measured 2026-09-14). With no plan text in the call and nothing to tell two live plans apart,
# the plan this session WROTE -- a Write or Edit into a plans directory, in the transcript the
# harness keeps -- is the one meant. Only with no such write does the newest by date decide, and
# then the gate says so in the context it returns, instead of choosing in silence.
sleep 1
sed 's/^| 1 | a | b |$/| 3 | a | b |/' "$PGP/good.md" > "$PGP/stale-draft.md"   # newer by date, and red
python3 - "$PG/t.jsonl" "$PG/t-wrote.jsonl" "$PGP/good.md" <<'PY'
import json, shutil, sys
shutil.copy(sys.argv[1], sys.argv[2])
with open(sys.argv[2], "a") as fh:
    fh.write(json.dumps({"message": {"content": [{"type": "tool_use", "name": "Write", "input": {"file_path": sys.argv[3], "content": "x"}}]}}) + "\n")
PY
run_hook plan-review-gate "{\"tool_name\":\"ExitPlanMode\",\"tool_input\":{},\"cwd\":\"$PGR\",\"transcript_path\":\"$PG/t-wrote.jsonl\"}"
! denied && ok "two live plans, no text in the call: the plan this session wrote is elected (the stale, red draft is not)" || fail "the plan this session wrote was not elected: $OUT"
run_hook plan-review-gate "$PG_EVENT"
denied && printf '%s' "$OUT" | grep -q 'live plans' && ok "with no write in the transcript either, two live plans are still refused by name" || fail "ambiguity resolved in silence: $OUT"
rm -f "$PGP/stale-draft.md"
run_hook plan-review-gate "$PG_EVENT"
! denied && printf '%s' "$OUT" | python3 -c 'import json,sys
d = json.load(sys.stdin); ctx = (d.get("hookSpecificOutput") or {}).get("additionalContext", "")
sys.exit(0 if "modification time" in ctx and "good.md" in ctx else 1)' \
  && ok "one plan, no text, no write: elected by date, and the gate SAYS so in additionalContext, naming the file" || fail "the date decided in silence: $OUT"
# The second home. The house norm keeps plans under docs/; a plan written there was invisible to
# this gate ("no plan found", the field case of 2026-09-08). The `plans` directory of docs.json is
# a candidate directory like plans_dir.
PGP_EMPTY="$PG/plans-empty"; mkdir -p "$PGP_EMPTY" "$PGR/docs/plans" "$PGR/.roadworthy"
printf '{"plans":"docs/plans"}\n' > "$PGR/.roadworthy/docs.json"
cp "$PGP/good.md" "$PGR/docs/plans/2026-01-01-0900-good.md"
CLAUDE_PLUGIN_OPTION_PLANS_DIR="$PGP_EMPTY" run_hook plan-review-gate "$PG_EVENT"
! denied && ok "a plan in the project's own plans directory (docs.json) is found and passes its pre-flight" || fail "the plan in docs/plans was not found: $OUT"
rm -rf "$PGR/docs" "$PGR/.roadworthy/docs.json"
unset CLAUDE_PLUGIN_OPTION_PLANS_DIR

rw_end
