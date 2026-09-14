#!/usr/bin/env bash
# Plans and reviews. The plans directory is shared by every project on the machine -- 101 plans of
# several projects when that was measured -- so a fixture that writes one always declares which
# project it belongs to.

# fx_plan <file> <project> [extra sections...] — a minimal plan with a project binding.
fx_plan() {
  local f="$1" proj="$2"; shift 2
  { printf '# plan\nproject: %s\n\n## Goal\n' "$proj"; [ $# -gt 0 ] && printf '%s\n' "$@"; } > "$f"
}

# fx_review <file> <plan name> <verdict> [round] — the sidecar review, bound to the plan by NAME.
fx_review() {
  printf 'plan: %s\nround: %s\nVERDICT: %s\n' "$2" "${4:-1}" "$3" > "$1"
}

# fx_rite_plan <file> <globs> <gates> — a plan scope-write.sh can open a front from: both sections
# are read as FENCED BLOCKS, never as prose bullets, because close.sh runs each gate with bash -c.
fx_rite_plan() {
  printf '# P\n## Escopo\n```\n%s\n```\n## Verificação\n```\n%s\n```\n' "$2" "$3" > "$1"
}
