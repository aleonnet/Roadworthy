#!/usr/bin/env bash
# Overnight mode. The marker and the rules file were built in the overnight-guard section and
# read again in the protect-paths freeze section two hundred lines later, through `ON` and `SUB`
# -- one of the eight crossings measured before the split.

# fx_night <dir> — a repository with the overnight marker in place.
fx_night() {
  fx_repo "$1"
  mkdir -p "$1/.roadworthy"
  echo '{"topic":"t"}' > "$1/.roadworthy/overnight"
}

# fx_night_rules <dir> <lines...> — the per-project deny:/freeze: rules.
fx_night_rules() {
  local d="$1"; shift
  printf '%s\n' "$@" > "$d/.roadworthy/overnight-rules"
}
