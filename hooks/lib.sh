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
deny() {
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
  local p="$1" d b
  [ -n "$p" ] || return 0
  d="$(dirname "$p")"; b="$(basename "$p")"
  d="$(cd "$d" 2>/dev/null && pwd -P || printf '%s' "$d")"
  case "$d" in
    */) printf '%s%s' "$d" "$b" ;;
    *)  printf '%s/%s' "$d" "$b" ;;
  esac
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
# Globs are translated to a regular expression, not matched with fnmatch:
# `**/` becomes any depth, `*` stops at a separator, `?` takes one character.
rw_glob_match() {
  python3 - "$1" "$2" <<'PY'
import os, re, sys
path, globs = sys.argv[1], [g.strip() for g in sys.argv[2].split(",") if g.strip()]
path = os.path.normpath(path)
def to_regex(g):
    g = os.path.normpath(g)
    out = ""
    i = 0
    while i < len(g):
        if g.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif g.startswith("**", i):
            out += ".*"; i += 2
        elif g[i] == "*":
            out += "[^/]*"; i += 1
        elif g[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(g[i]); i += 1
    return "^" + out + "$"
for g in globs:
    # Anchored at the root, always. A bare `README.md` used to also match `docs/README.md`,
    # because the old fallback stripped the leading anchor and searched at any separator.
    # A glob that means "at any depth" says so: `**/README.md`.
    if re.match(to_regex(g), path):
        sys.exit(0)
sys.exit(1)
PY
}
