#!/usr/bin/env bash
# tree-fingerprint.sh — one line that identifies exactly what was measured.
# Prints: <HEAD short sha> <tree hash of the working directory, tracked files> <dirty|clean>
set -euo pipefail
root="${1:-.}"
cd "$root"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository: $root" >&2; exit 1; }
head="$(git rev-parse --short=12 HEAD 2>/dev/null || echo no-commits)"
tree="$(git ls-files -z | xargs -0 shasum -a 256 2>/dev/null | shasum -a 256 | cut -c1-16)"
state="clean"
[ -z "$(git status --porcelain)" ] || state="dirty"
printf '%s %s %s\n' "$head" "$tree" "$state"
