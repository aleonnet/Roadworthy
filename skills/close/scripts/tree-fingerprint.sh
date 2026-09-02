#!/usr/bin/env bash
# tree-fingerprint.sh — one line that identifies exactly what was measured.
# Prints: <HEAD short sha> <content fingerprint> <clean|dirty>
#
# The fingerprint is `git write-tree` of a temporary index built from the
# working directory (tracked files plus untracked, minus ignored), so it
# follows CONTENT: a new commit with identical content keeps the fingerprint,
# a one-byte edit changes it. That is what makes "measured after the last
# commit" checkable.
set -euo pipefail
root="${1:-.}"
cd "$root"
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "not a git repository: $root" >&2; exit 1; }
head="$(git rev-parse --short=12 HEAD 2>/dev/null || echo no-commits)"
tmp_index="$(mktemp)"
rm -f "$tmp_index"
export GIT_INDEX_FILE="$tmp_index"
git add -A . >/dev/null 2>&1
# Transient Roadworthy state is not content: the scope lock, the recorded state
# and the ledgers change as a side effect of measuring, and must not move the
# fingerprint they are measured against.
git rm --cached -q --ignore-unmatch .roadworthy/scope .roadworthy/state .roadworthy/evidence.jsonl .roadworthy/denials.jsonl >/dev/null 2>&1 || true
tree="$(git write-tree | cut -c1-16)"
unset GIT_INDEX_FILE
rm -f "$tmp_index"
state="clean"
[ -z "$(git status --porcelain)" ] || state="dirty"
printf '%s %s %s\n' "$head" "$tree" "$state"
