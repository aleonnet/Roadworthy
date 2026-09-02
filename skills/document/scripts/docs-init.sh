#!/usr/bin/env bash
# docs-init.sh — create the documentation tree by role, idempotently.
#
# Roles, not names: the project chooses the directory for each role in
# .roadworthy/docs.json; the defaults below are used for anything missing.
# Existing files and directories are never overwritten. A second run produces
# no change. Prints one line per role: created | exists.
#
# Usage: docs-init.sh [project root]     (default: current directory)
set -euo pipefail
root="$(cd "${1:-.}" && pwd)"
cfg="$root/.roadworthy/docs.json"
mkdir -p "$root/.roadworthy"
if [ ! -f "$cfg" ]; then
  cat > "$cfg" <<'JSON'
{
  "map": "docs/README.md",
  "decisions": "docs/decisions",
  "plans": "docs/plans",
  "done": "docs/plans/done",
  "history": "docs/history",
  "reference": "docs/reference",
  "guides": "docs/guides",
  "archive": "docs/archive"
}
JSON
  echo "created  .roadworthy/docs.json (defaults)"
else
  echo "exists   .roadworthy/docs.json"
fi

role() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$cfg" "$1"; }

for r in decisions plans "done" history reference guides archive; do
  d="$(role "$r")"; [ -n "$d" ] || continue
  if [ -d "$root/$d" ]; then echo "exists   $d/ ($r)"; else mkdir -p "$root/$d"; echo "created  $d/ ($r)"; fi
done

map="$(role map)"
if [ -n "$map" ]; then
  if [ -f "$root/$map" ]; then echo "exists   $map (map)"; else
    mkdir -p "$(dirname "$root/$map")"
    cat > "$root/$map" <<EOF
# Documentation map

Read this first. Each role below is a directory declared in \`.roadworthy/docs.json\`.

| Role | Where | What lives there |
|---|---|---|
| decisions | \`$(role decisions)/\` | dated decision records (\`YYYY-MM-DD-HHMM-title.md\`, MADR status, Confirmation) |
| plans | \`$(role plans)/\` | live fronts: plans and handoffs; the newest handoff by name is the current state |
| done | \`$(role "done")/\` | concluded plans, each with a line in its \`README.md\` index |
| history | \`$(role history)/\` | closed fronts, moved here by \`close-front.sh\` with citations rewritten |
| reference | \`$(role reference)/\` | living canonical documents (undated names) |
| guides | \`$(role guides)/\` | how-to guides and runbooks |
| archive | \`$(role archive)/\` | excluded from checks, declared |

Resuming work: \`/roadworthy:resume\`. Checking the tree: \`docs-check.sh\`.
EOF
    echo "created  $map (map)"
  fi
fi

done_dir="$(role "done")"
if [ -n "$done_dir" ]; then
  if [ -f "$root/$done_dir/README.md" ]; then echo "exists   $done_dir/README.md (index)"; else
    printf '# Concluded plans\n\nOne line per file in this directory, as a markdown link to the file followed by what it delivered.\n' > "$root/$done_dir/README.md"
    echo "created  $done_dir/README.md (index)"
  fi
fi
