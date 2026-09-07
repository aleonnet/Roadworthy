#!/usr/bin/env bash
# pointers-check.sh — what an instruction file points at must exist.
#
# Two directions, both silent failures without this check:
#   1. instruction files (CLAUDE.md, AGENTS.md, READMEs) cite paths in backticks;
#      every cited path containing '/' must exist under one of the given roots
#      (`--root` may repeat; default: the file's own directory and its parent);
#   2. a memory directory (--memory <dir>): every markdown link in its MEMORY.md
#      resolves (relative to the directory, or absolute), and every *.md file in
#      the directory is reached from MEMORY.md (no orphan memory) — directly, or
#      through a sub-index MEMORY.md links to (an index split by theme keeps the
#      loaded index short; what the index reaches by links is still indexed).
# Usage: pointers-check.sh <instruction file...> [--root <dir>]... [--memory <dir>] [--allow <path>]...
set -euo pipefail
files=(); roots=(); memory=""; allow=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) roots+=("$2"); shift 2 ;;
    --memory) memory="$2"; shift 2 ;;
    --allow) allow+=("$2"); shift 2 ;;
    *) files+=("$1"); shift ;;
  esac
done
fail=0
problem() { echo "  [FAIL] $1"; fail=$((fail + 1)); }

for f in "${files[@]}"; do
  [ -f "$f" ] || { problem "$f: instruction file does not exist"; continue; }
  search=("${roots[@]}")
  [ "${#search[@]}" -gt 0 ] || search=("$(dirname "$f")" "$(dirname "$f")/..")
  while IFS= read -r cited; do
    [ -n "$cited" ] || continue
    case "$cited" in */*) ;; *) continue ;; esac
    skip=0; for a in "${allow[@]:-}"; do [ "$a" = "$cited" ] && skip=1; done; [ $skip = 1 ] && continue
    found=0
    for r in "${search[@]}"; do [ -e "$r/$cited" ] && { found=1; break; }; done
    [ $found = 1 ] || problem "$f: cites '$cited', which exists under none of: ${search[*]}"
  done < <(grep -o -E '`[A-Za-z0-9_./-]+\.(md|dart|py|sh|json|yaml|yml|toml|cc|h|js|ts)`' "$f" | tr -d '`' | sort -u)
done

if [ -n "$memory" ]; then
  idx="$memory/MEMORY.md"
  [ -f "$idx" ] || { problem "$idx does not exist"; }
  if [ -f "$idx" ]; then
    while IFS= read -r link; do
      [ -n "$link" ] || continue
      case "$link" in /*) target="$link" ;; *) target="$memory/$link" ;; esac
      [ -f "$target" ] || problem "MEMORY.md: link '$link' points at a missing file"
    done < <(grep -o -E '\]\([^)]+\.md\)' "$idx" | sed -E 's/^\]\(//; s/\)$//' | sort -u)
    # Every file the index reaches by markdown links, following links through the files it
    # reaches inside the memory directory (sub-indexes). Absolute links count as reached too.
    reached="$(python3 - "$memory" <<'PY'
import os, re, sys
d = sys.argv[1]
link = re.compile(r'\]\(([^)]+\.md)(?:#[^)]*)?\)')
seen, todo = set(), ["MEMORY.md"]
while todo:
    n = todo.pop()
    if n in seen:
        continue
    seen.add(n)
    p = n if os.path.isabs(n) else os.path.join(d, n)
    if not os.path.isfile(p) or os.path.dirname(os.path.abspath(p)) != os.path.abspath(d):
        continue
    with open(p, encoding="utf-8", errors="replace") as fh:
        todo.extend(link.findall(fh.read()))
print("\n".join(sorted(seen)))
PY
)"
    for m in "$memory"/*.md; do
      [ -e "$m" ] || continue
      n="$(basename "$m")"; [ "$n" = "MEMORY.md" ] && continue
      grep -q -F "${n%.md}" "$idx" && continue          # cited in the index text (link or stem)
      printf '%s\n' "$reached" | grep -q -x -F "$n" && continue   # reached through a sub-index
      problem "$n: memory file not reached from MEMORY.md (orphan)"
    done
  fi
fi

if [ "$fail" -eq 0 ]; then echo "pointers-check: OK"; else echo "pointers-check: $fail problem(s)"; exit 1; fi
