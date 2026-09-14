#!/usr/bin/env bash
# Shared helpers for Roadworthy hooks.
#
# Crash policy is declared per hook (RW_ON_CRASH, below), never implied.
# Guards fail closed: an internal error denies the action. Context injection
# fails open: a notice is shown and the prompt proceeds. Exit 2 is never used;
# denials are structured JSON with exit 0, the form every working plugin hook
# uses. UserPromptSubmit must never exit 2: it would erase the user's prompt.

set -u

# Every hook declares RW_ON_CRASH before sourcing this file:
#   deny  — a guard: on internal error the action is DENIED (a boundary that
#           fails open is not a boundary);
#   allow — context injection (UserPromptSubmit): on internal error a notice
#           is shown and the prompt proceeds (exit 2 there would erase it).
#   warn  — Stop: on internal error the turn is NOT blocked. Exit 2 blocks a turn,
#           and a guard that decides whether work may end must never trap a session.
# No default: a hook without a policy is itself an internal error.
rw_crash() {
  local where="$1"
  case "${RW_ON_CRASH:-}" in
    deny)
      python3 - "${RW_HOOK:-hook}" "$where" <<'PY'
import json, sys
print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "deny",
  "permissionDecisionReason": f"Roadworthy/{sys.argv[1]}: internal error at {sys.argv[2]}; failing closed. Fix the hook or disable it in /plugin."}}))
PY
      exit 0 ;;
    allow)
      echo "roadworthy/${RW_HOOK:-hook}: internal error at $where; guardrail skipped for this call" >&2
      exit 1 ;;
    warn)
      # Stop: exit 2 BLOCKS the turn, so an internal error there would trap the session in a
      # wall it cannot argue with. A hook that decides whether work may END fails open, loudly.
      echo "roadworthy/${RW_HOOK:-hook}: internal error at $where; not blocking the turn" >&2
      exit 1 ;;
    *)
      echo "roadworthy/${RW_HOOK:-hook}: no crash policy declared (RW_ON_CRASH)" >&2
      exit 1 ;;
  esac
}
# errtrace makes the ERR trap inherit into functions, command substitutions and subshells.
# Without it the trap is installed and silently absent exactly where the work happens, and a
# guard that declares RW_ON_CRASH=deny would fail OPEN inside any helper.
set -o errtrace
trap 'rw_crash "line $LINENO"' ERR

# Read the whole hook event from stdin once; expose a field reader.
rw_read_event() {
  RW_EVENT="$(cat)"
  [ -n "$RW_EVENT" ] || rw_crash "empty stdin"
  printf '%s' "$RW_EVENT" | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null || rw_crash "invalid JSON on stdin"
}

# rw_field <jq-like dotted path> — prints the value or empty. Pure python
# to avoid a jq dependency.
rw_field() {
  printf '%s' "$RW_EVENT" | python3 -c '
import json, sys
path = sys.argv[1].split(".")
try:
    obj = json.load(sys.stdin)
except Exception as e:
    sys.stderr.write("invalid JSON on stdin: %s\n" % e); sys.exit(3)
for key in path:
    if isinstance(obj, dict) and key in obj:
        obj = obj[key]
    else:
        print(""); sys.exit(0)
if isinstance(obj, (dict, list)):
    print(json.dumps(obj))
elif obj is None:
    print("")
else:
    print(obj)
' "$1"
}

# rw_option <KEY> <default> — plugin user option, from the environment
# Claude Code sets (CLAUDE_PLUGIN_OPTION_<KEY>), or the default.
rw_option() {
  local var="CLAUDE_PLUGIN_OPTION_$1"
  local value="${!var:-}"
  if [ -z "$value" ]; then printf '%s' "$2"; else printf '%s' "$value"; fi
}

rw_bool() { # rw_bool <value> — 0 when truthy
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *) return 1 ;;
  esac
}

# deny <event-name> <reason> — deliberate denial for PreToolUse.
#
# Every denial is also RECORDED. A guardrail that fires and leaves no trace is invisible to the
# next session and to the closing: the count of denials was only ever readable from an eval
# trace, which no real project has. The record carries the front it happened in, so "this fence
# denied three times while THIS front was open" becomes a fact instead of a memory.
#
# Recording never gets in the way of denying: any failure here is swallowed, and the denial
# goes out regardless. A ledger that could block a guard would be worse than no ledger.
rw_record_denial() {
  local reason="$1" cwd root data front
  cwd="$(rw_field cwd 2>/dev/null)" || return 0
  [ -n "$cwd" ] || return 0
  root="$(rw_root "$cwd" 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  data="$(rw_data_dir "$root")"
  mkdir -p "$data" 2>/dev/null || return 0
  front="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("plan_name", ""))
except Exception:
    print("")' "$root/.roadworthy/plan.snapshot" 2>/dev/null)" || front=""
  [ -n "$front" ] || front="$(rw_field session_id 2>/dev/null)"
  RW_R="$reason" RW_H="${RW_HOOK:-hook}" RW_C="$cwd" RW_F="$front" \
    python3 - "$data/denials.jsonl" <<'PY' 2>/dev/null || true
import json, os, sys, time
with open(sys.argv[1], "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
                         "hook": os.environ.get("RW_H", ""),
                         "reason": os.environ.get("RW_R", "")[:400],
                         "cwd": os.environ.get("RW_C", ""),
                         "front": os.environ.get("RW_F", "")}) + "\n")
PY
  return 0
}

deny() {
  rw_record_denial "$2" || true
  python3 - "$1" "$2" <<'PY'
import json, sys
print(json.dumps({"hookSpecificOutput": {
  "hookEventName": sys.argv[1],
  "permissionDecision": "deny",
  "permissionDecisionReason": "Roadworthy: " + sys.argv[2]}}))
PY
  exit 0
}

# rw_realpath <path> — the path with its directory resolved through symlinks.
# macOS hands the hooks a cwd under /var and `git rev-parse` answers under /private/var, so a
# prefix comparison between the two never matches and the "relative" path stays absolute. The
# glob matcher used to paper over that by matching a bare name at any depth; now that it is
# anchored, both sides have to be resolved before they are compared.
rw_realpath() {
  # Resolve the DEEPEST EXISTING ancestor and re-append what does not exist yet. Resolving only
  # dirname was not enough, measured by tests/attack.sh on 2026-09-14: `.roadworthy/stop-latch/s1`
  # escaped the foundation check entirely, because `stop-latch/` is created lazily and a `cd` into
  # a directory that does not exist fails -- so the path kept its unresolved form (`/var/...` on
  # macOS, where the root had resolved to `/private/var/...`), landed outside the root, and matched
  # nothing. The normal case for that directory is NOT existing, so the latch was unprotected
  # exactly when it mattered. The final component is deliberately NOT followed through a symlink;
  # see the declared limit in docs/reference/roadmap.md.
  local p="$1" d rest="" b
  [ -n "$p" ] || return 0
  d="$(dirname "$p")"; b="$(basename "$p")"
  rest="$b"
  while [ "$d" != "/" ] && [ "$d" != "." ] && [ ! -d "$d" ]; do
    rest="$(basename "$d")/$rest"
    d="$(dirname "$d")"
  done
  d="$(cd "$d" 2>/dev/null && pwd -P || printf '%s' "$d")"
  case "$d" in
    */) printf '%s%s' "$d" "$rest" ;;
    *)  printf '%s/%s' "$d" "$rest" ;;
  esac
}

# rw_data_dir <root> — where the evidence of a PROJECT lives: ROADWORTHY_DATA when it is set, else
# <root>/.roadworthy. CLAUDE_PLUGIN_DATA is deliberately not in this chain. Claude Code sets it for
# every hook to a directory that is per PLUGIN and shared by every project on the machine
# (~/.claude/plugins/data/<id>/ per the plugins reference), while a shell run by a person does not
# set it at all. Measured on 2026-09-14 at 13:33: the denials of the day were in that shared
# directory, the evidence ledger was in the project, and the stop gate reported six FRESH gates as
# MISSING because it looked where the hook environment pointed. One resolver, used by every writer
# and every reader, is what makes the two agree. The pin of the principles file is the one
# exception and says why in hooks/principles: that file lives outside every repository.
rw_data_dir() {
  local root="$1"
  if [ -n "${ROADWORTHY_DATA:-}" ]; then printf '%s' "$ROADWORTHY_DATA"; else printf '%s/.roadworthy' "$root"; fi
}

# rw_project_plans_dir <root> — the plan's SECOND home: the `plans` directory the project declares
# in .roadworthy/docs.json, resolved, or empty when the project declares none. Plan mode writes the
# plan in plans_dir (~/.claude/plans by default); the house documentation norm keeps it under docs/.
# A plan written in the second home was denied by the entry gate and unseen by the plan gate
# (measured 2026-09-08: "no plan found"), so the three of them read this one function.
rw_project_plans_dir() {
  local root="$1" rel
  [ -n "$root" ] && [ -f "$root/.roadworthy/docs.json" ] || return 0
  rel="$(python3 -c 'import json,sys
try:
    print((json.load(open(sys.argv[1])) or {}).get("plans", "") or "")
except Exception:
    print("")' "$root/.roadworthy/docs.json" 2>/dev/null)" || rel=""
  [ -n "$rel" ] || return 0
  case "$rel" in /*) rw_realpath "${rel%/}" ;; *) rw_realpath "$root/${rel%/}" ;; esac
}

# rw_root <dir> — the repository the directory belongs to, resolved, or the directory itself.
# A guard that reads `<cwd>/.roadworthy/...` is INERT one directory down: the session's cwd is
# wherever the agent happens to be, and the project's files live at the top level.
rw_root() {
  local d="$1"
  [ -n "$d" ] || return 0
  rw_realpath "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d")"
}

# rw_cmd_dir <command> <cwd> — the directory a shell command actually acts on: `git -C <dir>`,
# a leading `cd <dir> &&`, else the session's cwd. Generalised from the empty-staging check of
# guard-commit, which had the only copy of this reasoning.
rw_cmd_dir() {
  local command="$1" cwd="$2" dir
  dir="$(printf '%s' "$command" | sed -n -E 's/.*git[[:space:]]+-C[[:space:]]+([^[:space:]]+).*/\1/p' | head -1)"
  [ -n "$dir" ] || dir="$(printf '%s' "$command" | sed -n -E 's/^[[:space:]]*cd[[:space:]]+([^[:space:];&|]+)[[:space:]]*(&&|;).*/\1/p' | head -1)"
  [ -n "$dir" ] || dir="$cwd"
  dir="${dir/#\~/$HOME}"; dir="${dir%\"}"; dir="${dir#\"}"
  case "$dir" in /*) ;; *) dir="$cwd/$dir" ;; esac
  printf '%s' "$dir"
}

# rw_glob_match <path> <comma-separated globs> — 0 when any glob matches.
# The grammar lives in hooks/globmatch.py and nowhere else: the closing and the eval instrument
# read the same file, so "in scope" means one thing to the lock that denies an edit and to the
# instrument that counts it (until 0.6.1 rw-metrics answered through fnmatch, where `*` crosses
# a `/`). Anchored at the root, always: a bare `README.md` matches at the root only, and "at any
# depth" is spelled `**/README.md`.
rw_glob_match() {
  python3 "$(dirname "${BASH_SOURCE[0]}")/globmatch.py" "$1" "$2"
}
