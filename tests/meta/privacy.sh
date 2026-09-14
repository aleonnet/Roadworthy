#!/usr/bin/env bash
# privacy
# Run alone: bash tests/meta/privacy.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── privacy: the plugin must carry no personal data ──────────────────────────
section "privacy scan"
# A plugin source is what git tracks or would track: tracked files plus untracked files that are
# not ignored. Everything ignored is local machine state -- the Roadworthy ledgers, whose gate
# outputs carry the absolute paths of the machine that ran them, and evals/results/, which
# `claude plugin eval` fills with the same paths. Until 0.6.1 this scan read every file on disk,
# ignored or not, so it went red on any machine that had ever run an eval (measured 2026-09-14),
# and a stray untracked artefact such as a __pycache__ is exactly what it should catch.
# `.roadworthy/gates` is tracked and scanned like everything else.
sources="$(git ls-files --cached --others --exclude-standard | grep -v -E '^tests/' || true)"
if [ -n "$sources" ] && printf '%s\n' "$sources" | xargs grep -n -E '/Users/[a-z]+|/home/[a-z]+' -- 2>/dev/null | grep -q .; then
  fail "absolute home path found in plugin sources: $(printf '%s\n' "$sources" | xargs grep -l -E '/Users/[a-z]+|/home/[a-z]+' -- 2>/dev/null | tr '\n' ' ')"
else ok "no absolute home paths in what git tracks or would track"; fi
# The scan has to be able to say no, on exactly the kind of file that bit: untracked and not ignored.
printf '# %s\n' '/Users/someone/private' > planted-privacy-probe.txt
probe="$(git ls-files --cached --others --exclude-standard | grep -v -E '^tests/' | xargs grep -l -E '/Users/[a-z]+' -- 2>/dev/null || true)"
rm -f planted-privacy-probe.txt
printf '%s' "$probe" | grep -q 'planted-privacy-probe.txt' && ok "an untracked file with a home path is caught" || fail "the scan missed an untracked file with a home path"
# No member of the local-state list may be tracked: committing one publishes machine paths, and a
# tracked member dirties the tree at every front, which is what close.sh refuses to run on. The
# gates file is deliberately absent from this list: it is versioned like a test.
LOCAL_STATE='.roadworthy/scope .roadworthy/state .roadworthy/plan.snapshot .roadworthy/overnight
.roadworthy/evidence.jsonl .roadworthy/denials.jsonl .roadworthy/refutations.jsonl
.roadworthy/preflight.jsonl .roadworthy/readings.jsonl .roadworthy/stop-latch'
tracked_state=""
for f in $LOCAL_STATE; do
  git ls-files --error-unmatch "$f" >/dev/null 2>&1 && tracked_state="$tracked_state $f"
done
[ -z "$tracked_state" ] && ok "no local-state file is tracked by git" || fail "tracked local state:$tracked_state"
git ls-files --error-unmatch .roadworthy/gates >/dev/null 2>&1 \
  && ok "the gates file IS tracked (it survives the close; a clone needs it)" \
  || fail "the gates file is not tracked; close.sh refuses to close without it"
git ls-files --error-unmatch bin/__pycache__/rw-metricscpython-311.pyc >/dev/null 2>&1 \
  && fail "a compiled python artefact is tracked" \
  || ok "no compiled python artefact is tracked"

rw_end
