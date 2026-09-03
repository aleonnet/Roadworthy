#!/usr/bin/env bash
# overnight-close.sh — leave overnight mode with a hand-off the user audits in the morning.
#
# Usage: overnight-close.sh [--run]
# Refuses unless the marker exists, the tree is clean and `close.sh --check` reports every
# gate FRESH (`--run` runs close.sh first). Writes <YYYY-MM-DD-HHMM>-handoff-overnight-<topic>.md
# in the plans directory of .roadworthy/docs.json (fallback docs/plans), copying the blockers
# from the diary, then removes the marker and prints the hand-off path.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "overnight-close: not a git repository" >&2; exit 1; }
cd "$root"
refuse() { echo "overnight-close: $1" >&2; exit 1; }
[ -f .roadworthy/overnight ] || refuse "overnight mode is not on (no .roadworthy/overnight)"
[ -z "$(git status --porcelain)" ] || refuse "the tree is dirty; commit the last phase first"
close="$here/../../close/scripts/close.sh"
if [ "${1:-}" = "--run" ]; then bash "$close" || refuse "gates red — the night ends as gaps_found; fix and close again"; fi
check="$(bash "$close" --check 2>&1)" || { printf '%s\n' "$check" >&2; refuse "a gate is STALE or MISSING for this tree; run close.sh (or --run) after the last commit"; }
printf '%s' "$check" | grep -q -E '^\s+(STALE|MISSING|FRESH-RED)' && { printf '%s\n' "$check" >&2; refuse "a gate is not FRESH"; }

read -r topic diary plan <<< "$(python3 -c 'import json; m=json.load(open(".roadworthy/overnight")); print(m["topic"], m["diary"], m["plan"])')"
plans="docs/plans"
if [ -f .roadworthy/docs.json ]; then
  plans="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("plans","docs/plans"))' .roadworthy/docs.json)"
fi
mkdir -p "$plans"
closed_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(date +%Y-%m-%d-%H%M)"
handoff="$plans/$stamp-handoff-overnight-$topic.md"
[ ! -e "$handoff" ] || refuse "hand-off already exists: $handoff"
branch="$(git rev-parse --abbrev-ref HEAD)"
head="$(git rev-parse --short HEAD)"
upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null || true)"
if [ -n "$upstream" ]; then unpushed="$(git rev-list --count "$upstream..HEAD")"; else unpushed="no upstream"; fi
blockers="$(python3 - "$diary" <<'PY'
import sys
t = open(sys.argv[1], encoding="utf-8").read()
i = t.find("## Blockers for the morning")
if i < 0: print("- none"); sys.exit()
j = t.find("\n## ", i + 5)
body = t[i:j if j > 0 else len(t)].split("\n", 1)[1]
lines = [l for l in body.splitlines() if l.strip() and not l.strip().startswith("<!--")]
print("\n".join(lines) if lines else "- none")
PY
)"
python3 - "$here/../templates/handoff.md" "$handoff" "$topic" "$closed_iso" "$(basename "$root")" "$branch" "$head" "clean" "$unpushed" "$diary" "$plan" "$blockers" <<'PY'
import sys
tpl, out, topic, closed, repo, branch, head, tree, unpushed, diary, plan, blockers = sys.argv[1:13]
t = open(tpl, encoding="utf-8").read()
for k, v in {"topic": topic, "closed_iso": closed, "repo": repo, "branch": branch, "head": head, "tree": tree,
             "unpushed": unpushed, "diary": diary, "plan": plan, "blockers": blockers}.items():
    t = t.replace("{{%s}}" % k, v)
open(out, "w", encoding="utf-8").write(t)
PY
rm -f .roadworthy/overnight
echo "overnight-close: off at $closed_iso — hand-off $handoff (uncommitted: commit it, then the user orders the push)"
echo "$handoff"
