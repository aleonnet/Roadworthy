#!/usr/bin/env bash
# Toy git repositories. Fourteen sections built one of these inline before the split, each with
# its own spelling of the same four commands -- and one of them forgot `user.email`, which only
# showed up as a confusing failure three sections later.

# fx_repo <dir> — an initialised repository with an identity, no commits.
fx_repo() {
  mkdir -p "$1"
  git -C "$1" init -q
  git -C "$1" config user.email t@t
  git -C "$1" config user.name t
}

# fx_repo_committed <dir> [file] — the same, with one commit so HEAD resolves.
fx_repo_committed() {
  local d="$1" f="${2:-f}"
  fx_repo "$d"
  printf 'x\n' > "$d/$f"
  git -C "$d" add -A
  git -C "$d" commit -q -m base
}

# fx_front <dir> <globs> <gates> — a repository with a front already open, written by hand on
# purpose: this is the SHAPE the fences read, not the rite that produces it.
fx_front() {
  local d="$1" globs="$2" gates="$3"
  mkdir -p "$d/.roadworthy"
  printf '%s\n' "$globs" > "$d/.roadworthy/scope"
  printf '%s\n' "$gates" > "$d/.roadworthy/gates"
}
