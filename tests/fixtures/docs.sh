#!/usr/bin/env bash
# Documentation trees. docs-init.sh builds one, and four different sections needed the result:
# before the split they all reached into the ONE tree the docs-init section happened to leave
# behind, which is why `DI` crossed a section boundary and why none of them could run alone.

# fx_docs_tree <dir> — an initialised repository with the role tree docs-init.sh generates.
fx_docs_tree() {
  fx_repo "$1"
  bash "$ROOT/skills/document/scripts/docs-init.sh" "$1" >/dev/null
}

# fx_docs_tree_committed <dir> — the same, committed, so close.sh finds a clean tree.
fx_docs_tree_committed() {
  fx_docs_tree "$1"
  git -C "$1" add -A
  git -C "$1" commit -q -m base
}
