#!/usr/bin/env bash
# overnight-entry.sh — append to the open overnight diary; the timestamp is taken here.
#
# Usage:
#   overnight-entry.sh --phase <p> --decision <text> --reason <text> --source <primary source> [--ratify]
#   overnight-entry.sh --phase-done <p> --sha <commit> --gates <text>
#   overnight-entry.sh --blocker <text>
# Refuses without the marker, and refuses a decision without --source or with an empty one.
# Every entry that names a phase writes it to the marker as `phase`.
set -euo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "overnight-entry: not a git repository" >&2; exit 1; }
cd "$root"
refuse() { echo "overnight-entry: $1" >&2; exit 1; }
[ -f .roadworthy/overnight ] || refuse "overnight mode is not on (no .roadworthy/overnight)"
diary="$(python3 -c 'import json; print(json.load(open(".roadworthy/overnight"))["diary"])')"
[ -f "$diary" ] || refuse "diary not found: $diary"

phase="" decision="" reason="" source="" ratify="" done_phase="" sha="" gates="" blocker=""
while [ $# -gt 0 ]; do
  case "$1" in
    --phase) phase="${2:-}"; shift 2 ;;
    --decision) decision="${2:-}"; shift 2 ;;
    --reason) reason="${2:-}"; shift 2 ;;
    --source) source="${2:-}"; shift 2 ;;
    --ratify) ratify="yes"; shift ;;
    --phase-done) done_phase="${2:-}"; shift 2 ;;
    --sha) sha="${2:-}"; shift 2 ;;
    --gates) gates="${2:-}"; shift 2 ;;
    --blocker) blocker="${2:-}"; shift 2 ;;
    *) refuse "unknown argument: $1" ;;
  esac
done
ms="$(python3 -c 'import time; print(int(time.time()*1000))')"
iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [ -n "$blocker" ]; then
  section="## Blockers for the morning"; line="- \`$ms\` · $iso · $blocker"
elif [ -n "$done_phase" ]; then
  [ -n "$sha" ] || refuse "--phase-done needs --sha"
  section="## Phase ledger"; line="| $done_phase | \`$sha\` | ${gates:-—} | $iso |"
else
  [ -n "$phase" ] && [ -n "$decision" ] && [ -n "$reason" ] || refuse "a decision needs --phase, --decision and --reason"
  [ -n "$source" ] || refuse "a decision needs --source (a primary source; 'my judgement' is not one)"
  section="## Decisions"; line="- \`$ms\` · $iso · **$phase** · $decision · reason: $reason · source: $source${ratify:+ · ratify in the morning}"
fi
python3 - "$diary" "$section" "$line" <<'PY'
import sys
path, section, line = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
i = text.find(section)
if i < 0:
    sys.stderr.write(f"overnight-entry: section not found in diary: {section}\n"); sys.exit(1)
j = text.find("\n## ", i + len(section))
if j < 0: j = len(text)
block = text[i:j].rstrip("\n") + "\n" + line + "\n"
open(path, "w", encoding="utf-8").write(text[:i] + block + ("\n" + text[j:].lstrip("\n") if j < len(text) else ""))
PY
current="${done_phase:-$phase}"
if [ -n "$current" ]; then
  python3 - "$current" <<'PY'
import json, sys
m = json.load(open(".roadworthy/overnight")); m["phase"] = sys.argv[1]
json.dump(m, open(".roadworthy/overnight", "w"), indent=1)
PY
fi
echo "overnight-entry: $ms · $iso → $diary"
