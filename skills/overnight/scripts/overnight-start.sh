#!/usr/bin/env bash
# overnight-start.sh — enter overnight mode for an approved plan.
#
# Usage: overnight-start.sh <plan.md> <topic>
# Refuses (exit 1, EVERY missing precondition on stderr at once — a missing precondition is
# reported to the user, never satisfied by widening the plan) unless: no marker yet;
# .roadworthy/scope exists; the review next to the plan (<plan><review_suffix>, default
# .review.md) says VERDICT: APPROVED (what the user approved is what counts — no hash);
# the plan has a `## Overnight policy` (or `## Política da madrugada`) section; clean tree.
# On success writes `.roadworthy/overnight` (JSON, times taken here) and the diary in the
# decisions directory of .roadworthy/docs.json (fallback docs/decisions); prints the diary path.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plan="${1:?usage: overnight-start.sh <plan.md> <topic>}"
topic="${2:?usage: overnight-start.sh <plan.md> <topic>}"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "overnight-start: not a git repository" >&2; exit 1; }
cd "$root"
missing=()
miss() { missing+=("$1"); }
refuse() { echo "overnight-start: $1" >&2; exit 1; }

[ -f "$plan" ] || { echo "overnight-start: plan not found: $plan" >&2; exit 1; }
printf '%s' "$topic" | grep -q -E '^[a-z0-9][a-z0-9-]*$' || { echo "overnight-start: topic must be a lowercase slug (a-z, 0-9, -): $topic" >&2; exit 1; }
[ ! -f .roadworthy/overnight ] || { echo "overnight-start: overnight mode is already on ($(cat .roadworthy/overnight))" >&2; exit 1; }
[ -f .roadworthy/scope ] || miss "no .roadworthy/scope — declare the plan's scope first (/roadworthy:plan)"

suffix="${CLAUDE_PLUGIN_OPTION_REVIEW_SUFFIX:-.review.md}"
review="${plan%.md}$suffix"
if [ -f "$review" ]; then
  grep -q -E '^(VERDICT|VEREDITO):[[:space:]]*(APPROVED|APROVADO)[[:space:]]*$' "$review" || miss "the review is not APPROVED ($review): REJECTED or ESCALATE means the user has not decided yet"
else
  miss "no review next to the plan: $review — run the cold reviewer and record the verdict"
fi
grep -q -E '^## (Overnight policy|Política da madrugada|Politica da madrugada)[[:space:]]*$' "$plan" || miss "the plan has no '## Overnight policy' (or '## Política da madrugada') section (what is decided at night, what is reserved for the user)"
[ -z "$(git status --porcelain)" ] || miss "the tree is dirty; commit first (the review and the plan travel in the tree)"
if [ "${#missing[@]}" -gt 0 ]; then
  echo "overnight-start: ${#missing[@]} precondition(s) missing — report them, do not widen the plan:" >&2
  for m in "${missing[@]}"; do echo "  - $m" >&2; done
  exit 1
fi
sha="$(shasum -a 256 "$plan" | cut -d' ' -f1)"   # informational only: recorded in the diary

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
