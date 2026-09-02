#!/usr/bin/env bash
# docs-check.sh — language-agnostic fence for a docs tree, role-aware.
#
# Fails (exit 1) on:
#   * a dated file (YYYY-MM-DD…) without a `status:` line in its first 5 lines;
#   * a status outside: proposed | rejected | accepted | deprecated | superseded by <file>.md
#   * a dated file name outside YYYY-MM-DD-HHMM-<kebab>.md (optionally .plan.md);
#   * `superseded by <file>` whose target does not exist in the tree;
#   * a relative markdown link to a .md file that does not exist;
#   * with .roadworthy/docs.json present (role-aware):
#       - a file in the `done` role directory without a line in that directory's README.md;
#       - in the `plans` role directory, more than one handoff (`*-handoff-*.md`) that is not
#         marked `superseded by` — only the newest by NAME may be live.
# Usage: docs-check.sh <docs dir> [--since YYYY-MM-DD] [--config <docs.json>]
#   (files older than --since skip the name rule; config defaults to <docs dir>/../.roadworthy/docs.json)
set -euo pipefail
dir="${1:?usage: docs-check.sh <docs dir> [--since YYYY-MM-DD] [--config docs.json]}"; shift || true
since="0000-00-00"; cfg=""
while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --config) cfg="$2"; shift 2 ;;
    *) echo "docs-check: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -d "$dir" ] || { echo "docs-check: $dir is not a directory" >&2; exit 1; }
dir="$(cd "$dir" && pwd)"
[ -n "$cfg" ] || cfg="$(dirname "$dir")/.roadworthy/docs.json"

fail=0
problem() { echo "  [FAIL] $1"; fail=$((fail + 1)); }
vocab='^status: (proposed|rejected|accepted|deprecated|superseded by [^ ]+\.md)$'
dated='^[0-9]{4}-[0-9]{2}-[0-9]{2}'
pattern='^[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{4}-[a-z0-9-]+(\.plan)?\.md$'

while IFS= read -r -d '' f; do
  name="$(basename "$f")"
  status="$(head -5 "$f" | grep -m1 -E '^status:' || true)"
  if [[ "$name" =~ $dated ]]; then
    if [[ "${name:0:10}" > "$since" || "${name:0:10}" == "$since" ]]; then
      [[ "$name" =~ $pattern ]] || problem "$f: dated name outside YYYY-MM-DD-HHMM-description.md"
      [ -n "$status" ] || problem "$f: dated file without a status line"
    fi
  fi
  if [ -n "$status" ]; then
    [[ "$status" =~ $vocab ]] || problem "$f: '$status' outside the status vocabulary"
    if [[ "$status" =~ ^status:\ superseded\ by\ (.+)$ ]]; then
      target="${BASH_REMATCH[1]}"
      find "$dir" -name "$(basename "$target")" -print -quit | grep -q . || problem "$f: superseded by '$target', which does not exist"
    fi
  fi
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$link" in http*|/*|\#*) continue ;; esac
    link="${link%%#*}"
    [ -e "$(dirname "$f")/$link" ] || problem "$f: broken link '$link'"
  done < <(grep -o -E '\]\([^)]+\.md(#[^)]*)?\)' "$f" | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(find "$dir" -name '*.md' -not -path '*/archive/*' -print0)

if [ -f "$cfg" ]; then
  root="$(cd "$(dirname "$cfg")/.." && pwd)"
  role() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2], ""))' "$cfg" "$1"; }
  done_dir="$root/$(role "done")"
  if [ -n "$(role "done")" ] && [ -d "$done_dir" ]; then
    idx="$done_dir/README.md"
    for f in "$done_dir"/*.md; do
      [ -e "$f" ] || continue
      n="$(basename "$f")"; [ "$n" = "README.md" ] && continue
      [ -f "$idx" ] && grep -q -F "($n)" "$idx" || problem "$f: no line in $(role "done")/README.md"
    done
  fi
  plans_dir="$root/$(role plans)"
  if [ -n "$(role plans)" ] && [ -d "$plans_dir" ]; then
    live=()
    while IFS= read -r h; do
      head -5 "$h" | grep -q -E '^status: superseded by' || live+=("$(basename "$h")")
    done < <(find "$plans_dir" -maxdepth 1 -name '*-handoff-*.md' | sort)
    if [ "${#live[@]}" -gt 1 ]; then
      problem "$(role plans): ${#live[@]} live handoffs (${live[*]}); only the newest by name may stay unsuperseded"
    fi
  fi
fi

if [ "$fail" -eq 0 ]; then echo "docs-check: OK ($dir)"; else echo "docs-check: $fail problem(s) in $dir"; exit 1; fi
