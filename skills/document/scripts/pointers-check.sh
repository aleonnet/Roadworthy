#!/usr/bin/env bash
# pointers-check.sh — what an instruction file points at must exist.
#
# Two directions, both silent failures without this check:
#   1. instruction files (CLAUDE.md, AGENTS.md, READMEs) cite paths in backticks;
#      every cited path containing '/' must exist under one of the given roots
#      (`--root` may repeat; default: the file's own directory and its parent);
#   2. a memory directory (--memory <dir>): every markdown link in its MEMORY.md
#      resolves (relative to the directory, or absolute), and every *.md file in
#      the directory is cited by MEMORY.md (no orphan memory).
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
    for m in "$memory"/*.md; do
      [ -e "$m" ] || continue
      n="$(basename "$m")"; [ "$n" = "MEMORY.md" ] && continue
      grep -q -F "${n%.md}" "$idx" || problem "$n: memory file not cited by MEMORY.md (orphan)"
    done
  fi
fi

if [ "$fail" -eq 0 ]; then echo "pointers-check: OK"; else echo "pointers-check: $fail problem(s)"; exit 1; fi
