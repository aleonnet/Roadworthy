#!/usr/bin/env bash
# overnight-start.sh — enter overnight mode for an approved plan.
#
# Usage: overnight-start.sh <plan.md> <topic>
# Refuses (exit 1, reason on stderr) unless: no marker yet; .roadworthy/scope exists; the
# review file next to the plan (<plan><review_suffix>, default .review.md) says
# VERDICT: APPROVED for the plan's current SHA-256; the plan has a `## Overnight policy`
# section; clean tree. On success writes `.roadworthy/overnight` (JSON, times
# taken here) and the diary in the decisions directory of .roadworthy/docs.json
# (fallback docs/decisions); prints the diary path.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan="${1:?usage: overnight-start.sh <plan.md> <topic>}"
topic="${2:?usage: overnight-start.sh <plan.md> <topic>}"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "overnight-start: not a git repository" >&2; exit 1; }
cd "$root"
refuse() { echo "overnight-start: $1" >&2; exit 1; }

[ -f "$plan" ] || refuse "plan not found: $plan"
printf '%s' "$topic" | grep -q -E '^[a-z0-9][a-z0-9-]*$' || refuse "topic must be a lowercase slug (a-z, 0-9, -): $topic"
[ ! -f .roadworthy/overnight ] || refuse "overnight mode is already on ($(cat .roadworthy/overnight))"
[ -f .roadworthy/scope ] || refuse "no .roadworthy/scope — declare the plan's scope first (/roadworthy:plan)"

suffix="${CLAUDE_PLUGIN_OPTION_REVIEW_SUFFIX:-.review.md}"
review="${plan%.md}$suffix"
[ -f "$review" ] || refuse "no review next to the plan: $review — run the cold reviewer and bind the verdict to the hash"
sha="$(shasum -a 256 "$plan" | cut -d' ' -f1)"
grep -q -E "^plan-sha256:[[:space:]]*${sha}[[:space:]]*$" "$review" || refuse "the review does not match the plan's current SHA-256 ($sha); the plan changed after the review"
grep -q -E '^VERDICT:[[:space:]]*APPROVED[[:space:]]*$' "$review" || refuse "the review is not APPROVED"
grep -q -E '^## Overnight policy[[:space:]]*$' "$plan" || refuse "the plan has no '## Overnight policy' section (what is decided at night, what is reserved for the user)"
[ -z "$(git status --porcelain)" ] || refuse "the tree is dirty; commit first (the review and the plan travel in the tree)"

decisions="docs/decisions"
if [ -f .roadworthy/docs.json ]; then
  decisions="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("decisions","docs/decisions"))' .roadworthy/docs.json)"
fi
mkdir -p "$decisions"
started_ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
started_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
stamp="$(date +%Y-%m-%d-%H%M)"
diary="$decisions/$stamp-overnight-$topic.md"
[ ! -e "$diary" ] || refuse "diary already exists: $diary"
sed -e "s|{{topic}}|$topic|g" -e "s|{{plan}}|$plan|g" -e "s|{{plan_sha}}|$sha|g" \
    -e "s|{{started_iso}}|$started_iso|g" -e "s|{{started_ms}}|$started_ms|g" \
    "$here/../templates/diary.md" > "$diary"
python3 - "$plan" "$sha" "$topic" "$diary" "$started_ms" "$started_iso" <<'PY'
import json, sys
plan, sha, topic, diary, ms, iso = sys.argv[1:7]
json.dump({"started_ms": int(ms), "started_iso": iso, "plan": plan, "plan_sha256": sha,
           "topic": topic, "diary": diary, "phase": ""}, open(".roadworthy/overnight", "w"), indent=1)
PY
echo "overnight-start: on since $started_iso ($started_ms ms) — diary $diary"
echo "$diary"
