#!/usr/bin/env bash
# privacy
# Run alone: bash tests/meta/privacy.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── privacy: the plugin must carry no personal data ──────────────────────────
section "privacy scan"
# Local Roadworthy state is not a plugin source: close.sh writes a gate's own output there, which
# carries the absolute paths of the machine that ran it, and the snapshot carries the plan's path.
# The ten members are gitignored, and excluded here for the same reason tree-fingerprint.sh leaves
# them out of the fingerprint. Everything else, `.roadworthy/gates` included, is scanned.
LEDGERS='^\./\.roadworthy/(scope|state|plan\.snapshot|overnight|evidence\.jsonl|denials\.jsonl|refutations\.jsonl|preflight\.jsonl|readings\.jsonl|stop-latch/)'
if grep -r -n -E '/Users/[a-z]+|/home/[a-z]+' --include='*' . --exclude-dir=.git --exclude-dir=tests | grep -v 'tests/' | grep -v -E "$LEDGERS" >/dev/null; then
  fail "absolute home path found in plugin sources"
else ok "no absolute home paths"; fi
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
