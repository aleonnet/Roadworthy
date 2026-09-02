#!/usr/bin/env bash
# close-front.sh — move the documents of a closed front into history, keeping every link alive.
#
# Dry-run by default: prints each `git mv` and each link rewrite. `--apply` executes them and
# runs docs-check at the end. Links are rewritten repository-wide for relative markdown links
# that point at a moved file (by basename), so nothing dangles.
#
# Usage: close-front.sh <topic> <file...> [--apply] [--root <repo root>]
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
topic="${1:?usage: close-front.sh <topic> <file...> [--apply]}"; shift
apply=0; root=""; files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1; shift ;;
    --root) root="$2"; shift 2 ;;
    *) files+=("$1"); shift ;;
  esac
done
[ "${#files[@]}" -gt 0 ] || { echo "close-front: give at least one file" >&2; exit 1; }
[ -n "$root" ] || root="$(git rev-parse --show-toplevel)"
cd "$root"
cfg=".roadworthy/docs.json"
[ -f "$cfg" ] || { echo "close-front: $cfg not found; run docs-init.sh first" >&2; exit 1; }
history="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["history"])' "$cfg")"
dest="$history/$topic"

plan=()
for f in "${files[@]}"; do
  [ -f "$f" ] || { echo "close-front: $f does not exist" >&2; exit 1; }
  plan+=("$f")
done

echo "== moves ($([ $apply = 1 ] && echo APPLY || echo DRY-RUN))"
for f in "${plan[@]}"; do echo "  git mv $f -> $dest/$(basename "$f")"; done

echo "== link rewrites"
rewrites=0
for f in "${plan[@]}"; do
  base="$(basename "$f")"
  while IFS=: read -r src _; do
    [ -n "$src" ] || continue
    case " ${plan[*]} " in *" $src "*) continue ;; esac   # links inside moved files are re-resolved after the move
    old_rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "$f" "$src")"
    new_rel="$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], os.path.dirname(sys.argv[2])))' "$dest/$base" "$src")"
    grep -q -F "($old_rel" "$src" || continue
    echo "  $src: ($old_rel) -> ($new_rel)"
    rewrites=$((rewrites + 1))
    if [ $apply = 1 ]; then
      python3 - "$src" "$old_rel" "$new_rel" <<'PY'
import sys
p, old, new = sys.argv[1:4]
s = open(p, encoding="utf-8").read()
open(p, "w", encoding="utf-8").write(s.replace("(" + old, "(" + new))
PY
    fi
  done < <(grep -r -l -F "$base" --include='*.md' . 2>/dev/null | sed 's|^\./||' | sed 's/$/:/')
done
echo "  $rewrites rewrite(s)"

if [ $apply = 1 ]; then
  mkdir -p "$dest"
  for f in "${plan[@]}"; do git mv "$f" "$dest/$(basename "$f")"; done
  docs_dir="$(python3 -c 'import json,sys,os; print(os.path.dirname(json.load(open(sys.argv[1]))["decisions"]))' "$cfg")"
  bash "$here/../../document/scripts/docs-check.sh" "$docs_dir" --config "$cfg"
else
  echo "dry-run only; re-run with --apply to execute"
fi
