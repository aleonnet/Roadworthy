#!/usr/bin/env bash
# docs-check.sh — language-agnostic fence for a docs tree.
#
# Fails (exit 1) on:
#   * a dated file (YYYY-MM-DD…) without a `status:` line in its first 5 lines;
#   * a status outside: proposed | rejected | accepted | deprecated | superseded by <file>.md
#   * a dated file name outside YYYY-MM-DD-HHMM-<kebab>.md (optionally .plan.md);
#   * `superseded by <file>` whose target does not exist in the tree;
#   * a relative markdown link to a .md file that does not exist.
# Usage: docs-check.sh <docs dir> [--since YYYY-MM-DD]   (files older than --since skip the name rule)
set -euo pipefail
dir="${1:?usage: docs-check.sh <docs dir> [--since YYYY-MM-DD]}"; shift || true
since="0000-00-00"
[ "${1:-}" = "--since" ] && since="${2:?}"
[ -d "$dir" ] || { echo "docs-check: $dir is not a directory" >&2; exit 1; }

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
  # relative links to .md files
  while IFS= read -r link; do
    [ -n "$link" ] || continue
    case "$link" in http*|/*|\#*) continue ;; esac
    link="${link%%#*}"
    [ -e "$(dirname "$f")/$link" ] || problem "$f: broken link '$link'"
  done < <(grep -o -E '\]\([^)]+\.md(#[^)]*)?\)' "$f" | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(find "$dir" -name '*.md' -print0)

if [ "$fail" -eq 0 ]; then echo "docs-check: OK ($dir)"; else echo "docs-check: $fail problem(s) in $dir"; exit 1; fi
