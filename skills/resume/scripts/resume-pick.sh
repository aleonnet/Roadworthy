#!/usr/bin/env bash
# resume-pick.sh — which handoff is the current one?
#
# Picks the newest handoff BY NAME (names start with YYYY-MM-DD-HHMM, so alphabetical
# order is chronological), never by modification time: marking an old handoff as
# superseded makes it newer on disk than the new one. Follows `superseded by` pointers
# and fails on a cycle or on a pointer to something older.
# Usage: resume-pick.sh [project root]   → prints the path of the handoff to read first
set -euo pipefail
root="$(cd "${1:-.}" && pwd)"
cfg="$root/.roadworthy/docs.json"
[ -f "$cfg" ] || { echo "resume-pick: $cfg not found; run docs-init.sh" >&2; exit 1; }
plans="$root/$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plans"])' "$cfg")"
[ -d "$plans" ] || { echo "resume-pick: plans directory $plans does not exist" >&2; exit 1; }
newest="$(find "$plans" -maxdepth 1 -name '*-handoff-*.md' -print | sed 's|.*/||' | sort | tail -1)"
[ -n "$newest" ] || { echo "resume-pick: no handoff in $plans" >&2; exit 1; }
seen=()
current="$newest"
for _ in 1 2 3 4 5 6 7 8; do
  for s in "${seen[@]:-}"; do [ "$s" = "$current" ] && { echo "resume-pick: cycle in superseded-by at $current" >&2; exit 1; }; done
  seen+=("$current")
  target="$(head -5 "$plans/$current" | grep -m1 -E '^status: superseded by ' | sed -E 's/^status: superseded by //' || true)"
  if [ -z "$target" ]; then echo "$plans/$current"; exit 0; fi
  [ -f "$plans/$target" ] || { echo "resume-pick: $current is superseded by '$target', which does not exist" >&2; exit 1; }
  [[ "$target" > "$current" ]] || { echo "resume-pick: $current is superseded by '$target', which is not newer by name" >&2; exit 1; }
  current="$target"
done
echo "resume-pick: superseded-by chain longer than 8" >&2; exit 1
