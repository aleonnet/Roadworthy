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
    *)
      echo "roadworthy/${RW_HOOK:-hook}: no crash policy declared (RW_ON_CRASH)" >&2
      exit 1 ;;
  esac
}
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

# rw_glob_match <path> <comma-separated globs> — 0 when any glob matches.
# Globs use the shell's `**`-aware matching via python fnmatch after
# normalising `**/` to match any depth.
rw_glob_match() {
  python3 - "$1" "$2" <<'PY'
import fnmatch, os, re, sys
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
    if re.match(to_regex(g), path) or re.search("(^|/)" + to_regex(g)[1:], path):
        sys.exit(0)
sys.exit(1)
PY
}
