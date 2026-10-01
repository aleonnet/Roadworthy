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
# A guard that DIES is not a guard that answered. `set -u` on an unbound variable and a syntax
# error inside a command substitution end the script without ever reaching the ERR trap, and
# Claude Code treats a hook that exits non-zero (other than 2) as a non-blocking error: the tool
# call goes ahead. Measured on 2026-10-01 while writing the commit guard: bash 3.2 could not parse
# one of its lines, the hook died with status 1, and the commit it existed to refuse was allowed.
# So for a guard the EXIT itself is watched: any status but 0 leaves as a denial.
rw_on_exit() {
  local rc=$?
  trap - EXIT ERR
  if [ "$rc" -ne 0 ] && [ "${RW_ON_CRASH:-}" = deny ]; then
    rw_crash "an early exit with status $rc"
  fi
  exit "$rc"
}
trap rw_on_exit EXIT

# Read the whole hook event from stdin once; expose a field reader.
#
# The event is parsed ONCE. Until 0.7.0 every rw_field was its own python3, and a guard read five
# or six fields: measured on 2026-10-01, one call of the entry gate cost 1.0 to 1.3 s of wall
# clock, nearly all of it interpreter start-up, on every single tool call of a session. The fields
# the hooks read are extracted here in the same process that validates the JSON, and handed to the
# shell as quoted assignments (shlex.quote, so a command with quotes and newlines survives `eval`).
RW_FIELDS="cwd tool_name session_id transcript_path scratchpad_dir agent_id agent_type hook_event_name permission_mode last_assistant_message stop_hook_active source prompt tool_response tool_input.command tool_input.file_path tool_input.notebook_path tool_input.plan tool_input.planFilePath"
rw_read_event() {
  local parsed
  RW_EVENT="$(cat)"
  [ -n "$RW_EVENT" ] || rw_crash "empty stdin"
  parsed="$(printf '%s' "$RW_EVENT" | python3 -c '
import json, re, shlex, sys
try:
    event = json.load(sys.stdin)
except Exception:
    sys.exit(3)
for path in sys.argv[1].split():
    obj = event
    for key in path.split("."):
        obj = obj[key] if isinstance(obj, dict) and key in obj else None
    if isinstance(obj, bool):
        obj = "true" if obj else "false"      # as json.dumps spells it, not as Python does
    elif isinstance(obj, (dict, list)):
        obj = json.dumps(obj)
    elif obj is None:
        obj = ""
    print("RW_F_%s=%s" % (re.sub(r"[^A-Za-z0-9]", "_", path), shlex.quote(str(obj))))
' "$RW_FIELDS" 2>/dev/null)" || rw_crash "invalid JSON on stdin"
  eval "$parsed"
  RW_EVENT_PARSED=1
}

# rw_field <jq-like dotted path> — prints the value or empty. A field parsed by rw_read_event is
# answered from the shell; any other is read from the event. Pure python, no jq dependency.
rw_field() {
  local var
  if [ -n "${RW_EVENT_PARSED:-}" ]; then
    case " $RW_FIELDS " in
      *" $1 "*) var="RW_F_$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '_')"; printf '%s\n' "${!var:-}"; return 0 ;;
    esac
  fi
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
#
# WHO was denied (0.7.0). The record carries the session, the subagent (`agent_id`, "Present only
# when the hook fires inside a subagent call" -- hooks reference) and whether a scope was open.
# The count that turns into a warning looked at every record with the front's name: denials of a
# subagent, of another session and of fixtures run by the test suite were all charged to the main
# agent, and the warning never expired (field note, 2026-09-30: "rite-gate: 4 denials" shown to a
# session that had been denied once). What is counted now: this hook, this session, the main
# agent, with a scope open, since the front opened. Closing the front ends it without deleting a
# line. And the THIRD such denial says so in its own reason, in the same turn -- until 0.7.0 the
# warning only reached the next prompt.
#
# It prints what the denial should add to its reason: the third-strike line, or a note that the
# record could not be written.
rw_record_denial() {
  local reason="$1" cwd root data front
  cwd="$(rw_field cwd 2>/dev/null)" || return 0
  [ -n "$cwd" ] || return 0
  # The record belongs to the repository the denied TARGET is in (a hook that knows it sets
  # RW_DENIAL_ROOT); else to the one the session stands in.
  root="${RW_DENIAL_ROOT:-}"
  [ -n "$root" ] || root="$(rw_root "$cwd" 2>/dev/null)" || return 0
  [ -n "$root" ] || return 0
  data="$(rw_data_dir "$root")"
  # A refusal never CREATES the plugin's directory in a repository that has none. It did, and the
  # ledger it wrote there became an untracked file the agent may not remove -- inside a submodule
  # that made the parent's front impossible to close, for ever (adversarial simulation,
  # 2026-10-01). A repository with no .roadworthy has no ledger; the denial still goes out.
  [ -d "$data" ] || return 0
  front="$(python3 -c 'import json,sys
try:
    print(json.load(open(sys.argv[1])).get("plan_name", ""))
except Exception:
    print("")' "$root/.roadworthy/plan.snapshot" 2>/dev/null)" || front=""
  [ -n "$front" ] || front="$(rw_field session_id 2>/dev/null)"
  RW_R="$reason" RW_H="${RW_HOOK:-hook}" RW_C="$cwd" RW_F="$front" \
  RW_S="$(rw_field session_id 2>/dev/null)" RW_A="$(rw_field agent_id 2>/dev/null)" \
    python3 - "$data/denials.jsonl" "$root" <<'PY' 2>/dev/null || printf ' (This denial could not be recorded in %s.)' "$data/denials.jsonl"
import json, os, sys, time
ledger, root = sys.argv[1], sys.argv[2]
hook, session, agent = os.environ.get("RW_H", ""), os.environ.get("RW_S", ""), os.environ.get("RW_A", "")
scope = os.path.join(root, ".roadworthy", "scope")
scope_open = os.path.exists(scope)
opened = ""
try:
    opened = (json.load(open(os.path.join(root, ".roadworthy", "plan.snapshot"), encoding="utf-8")) or {}).get("ts", "")
except Exception:
    opened = ""
now = time.strftime("%Y-%m-%dT%H:%M:%S")
# The KIND of refusal: its text with what varies taken out (quoted names, paths, numbers). Three
# different refusals in a front are an agent finding its way; three of one kind are a pattern.
import re
kind = " ".join(re.sub(r"'[^']*'|\S*/\S*|\d+", " ", os.environ.get("RW_R", "")).split())[:60]
with open(ledger, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": now, "hook": hook,
                         "reason": os.environ.get("RW_R", "")[:400],
                         "cwd": os.environ.get("RW_C", ""),
                         "front": os.environ.get("RW_F", ""),
                         "session": session, "agent": agent, "scope_open": scope_open, "kind": kind}) + "\n")
if scope_open and not agent and session:
    n = 0
    for line in open(ledger, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if (r.get("hook") == hook and r.get("kind") == kind and r.get("session") == session and not r.get("agent")
                and r.get("scope_open") and r.get("ts", "") >= opened):
            n += 1
    if n >= 3:
        sys.stdout.write(" THIS FENCE HAS NOW DENIED THE SAME WAY %d TIMES IN THIS FRONT. Three refusals are not an obstacle to "
                         "route around; they are the front telling you that what you are trying to do is not what was "
                         "approved. Say so to the owner, or take it to the plan." % n)
PY
  return 0
}

deny() {
  local more
  more="$(rw_record_denial "$2" 2>/dev/null || true)"
  set -- "$1" "$2$more"
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

# rw_is_plan_file <absolute path> <root> — 0 when the path is a PLAN: a `.md` file whose directory
# is exactly one of the plan's two homes (plans_dir, or the `plans` directory of the project's
# docs.json). The plan is what opens a front, so it cannot need one. Until 0.7.0 the whole
# DIRECTORY was exempt, at any depth and for any kind of file -- so anything dropped under
# docs/plans/ was editable with no front, and a docs.json pointing `plans` at `.` exempted the
# repository (field note, 2026-09-18). A home that IS the repository root, or outside it, is not
# a home.
rw_is_plan_file() {
  local t="$1" root="$2" tdir plans project
  case "$t" in *.md) ;; *) return 1 ;; esac
  tdir="$(dirname "$t")"
  tdir="$(cd "$tdir" 2>/dev/null && pwd -P || printf '%s' "$tdir")"
  plans="$(rw_option PLANS_DIR "")"
  [ -n "$plans" ] || plans="$HOME/.claude/plans"
  plans="$(rw_realpath "${plans%/}")"
  if [ "$tdir" = "$plans" ] && [ "$plans" != "$root" ]; then return 0; fi
  project="$(rw_project_plans_dir "$root")"
  if [ -n "$project" ] && [ "$tdir" = "$project" ]; then
    case "$project" in "$root"/*) return 0 ;; esac
  fi
  return 1
}

# rw_root <dir> — the repository the directory belongs to, resolved, or the directory itself.
# A guard that reads `<cwd>/.roadworthy/...` is INERT one directory down: the session's cwd is
# wherever the agent happens to be, and the project's files live at the top level.
rw_root() {
  local d="$1"
  [ -n "$d" ] || return 0
  rw_realpath "$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$d")"
}

# rw_target_root <absolute path> — the repository a FILE belongs to: the top level of the
# repository that holds its deepest existing ancestor, resolved; empty when it is in none.
# Until 0.7.0 every fence resolved the repository from the SESSION's directory, and that was wrong
# in both directions (field, 2026-09-18 and 2026-09-22): with the session in one repository, an
# edit to a file of ANOTHER was judged by the wrong scope and the wrong protected list -- let
# through when the session's repository had no lock, denied when it had one that knew nothing
# about that file. The scope, the state and the protected list that count are the ones of the
# repository the file is in.
rw_target_root() {
  local d="$1" top
  [ -n "$d" ] || return 0
  while [ "$d" != "/" ] && [ "$d" != "." ] && [ ! -d "$d" ]; do d="$(dirname "$d")"; done
  # The `|| true` is INSIDE the substitution on purpose: with errtrace the ERR trap is inherited
  # by the subshell, and a failing git there would answer with a denial instead of with nothing.
  top="$(git -C "$d" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] || return 0
  # A repository INSIDE another one -- a submodule, a vendored checkout -- that has no
  # .roadworthy of its own answers to the nearest repository above it that has one: its files
  # are, to the project that holds it, paths like any other (in or out of the scope, ignored or
  # not). Asked for a front of its own, `rm -rf vendor/lib` was refused with a front open.
  # With no such repository above, it is its own.
  local at="$top" up n=0
  while [ ! -d "$top/.roadworthy" ] && [ "$n" -lt 8 ]; do
    up="$(git -C "$(dirname "$at")" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$up" ] && [ "$up" != "$at" ] || break
    if [ -d "$up/.roadworthy" ]; then top="$up"; break; fi
    at="$up"; n=$((n + 1))
  done
  rw_realpath "$top"
}

# rw_agent_place <absolute path> — 0 when the path is one of the agent's own working places:
# the session scratchpad (`scratchpad_dir`, a common field of every hook event since Claude Code
# 2.1.257: "Path to the session's scratchpad directory, where Claude keeps temporary working
# files") or the project's auto-memory directory, next to the transcript. Neither is repository
# work, whatever git says about where they sit: a toy repository built in the scratchpad to try
# something out is a scratch file with a .git in it, and a memory note is not a change to anything.
RW_PLACES_READ=""; RW_SCRATCHPAD=""; RW_MEMORY=""
rw_agent_place() {
  local t="$1" d
  if [ -z "$RW_PLACES_READ" ]; then          # read once per event: a command can name many targets
    RW_PLACES_READ=1
    d="$(rw_field scratchpad_dir 2>/dev/null)" || d=""
    [ -z "$d" ] || RW_SCRATCHPAD="$(rw_realpath "${d%/}")"
    d="$(rw_field transcript_path 2>/dev/null)" || d=""
    [ -z "$d" ] || RW_MEMORY="$(rw_realpath "$(dirname "$d")/memory")"
  fi
  if [ -n "$RW_SCRATCHPAD" ]; then
    case "$t" in "$RW_SCRATCHPAD"|"$RW_SCRATCHPAD"/*) return 0 ;; esac
  fi
  if [ -n "$RW_MEMORY" ]; then
    case "$t" in "$RW_MEMORY"|"$RW_MEMORY"/*) return 0 ;; esac
  fi
  return 1
}

# rw_temp_place <absolute path> — 0 when the path is under a temporary directory of the system.
# A file there, in no repository, is nobody's project: the scope of the session's front has
# nothing to say about it (it denied 35 such writes in one session, field 2026-09-22).
rw_temp_place() {
  local t="$1" d
  case "$t" in
    /tmp/*|/private/tmp/*|/var/tmp/*|/private/var/tmp/*|/var/folders/*|/private/var/folders/*|/dev/*) return 0 ;;
  esac
  if [ -n "${TMPDIR:-}" ]; then
    d="$(rw_realpath "${TMPDIR%/}")"
    case "$t" in "$d"|"$d"/*) return 0 ;; esac
  fi
  return 1
}

# rw_list_globs <file> — the globs a list file declares (one per line, `#` comments), joined by
# commas; empty when the file does not exist or declares none.
rw_list_globs() {
  [ -f "$1" ] || return 0
  grep -v -E '^[[:space:]]*(#|$)' "$1" | tr '\n' ',' | sed 's/,$//' || true
}

# rw_protected_globs <root> — what may never be edited in a repository: the user's
# `protected_paths` option joined with the project's own .roadworthy/protected. One assembly,
# read by protect-paths (the edit tools), rite-gate (the shell), guard-commit (the index) and
# nothing else, so the three doors cannot disagree about what is protected.
rw_protected_globs() {
  local root="$1" globs project
  globs="$(rw_option PROTECTED_PATHS "")"
  if [ -n "$root" ]; then
    project="$(rw_list_globs "$root/.roadworthy/protected")"
    [ -z "$project" ] || globs="${globs:+$globs,}$project"
  fi
  printf '%s' "$globs"
}

# rw_frozen_globs <root> — the `freeze:` globs of .roadworthy/overnight-rules, only while the night
# marker exists: version files and release notes wait for the morning.
rw_frozen_globs() {
  local root="$1"
  [ -n "$root" ] && [ -f "$root/.roadworthy/overnight" ] && [ -f "$root/.roadworthy/overnight-rules" ] || return 0
  grep -E '^[[:space:]]*freeze:' "$root/.roadworthy/overnight-rules" | sed 's/^[[:space:]]*freeze:[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$' | tr '\n' ',' | sed 's/,$//' || true
}

# rw_free_globs <root> — .roadworthy/free: the paths the OWNER declares outside the rite. A write
# there needs no front and no scope: private notes, drafts, a scratch area inside the repository.
# It is the mirror of .roadworthy/protected and, like it, the owner's file -- the agent neither
# edits nor removes it (rite-gate). Measured on 2026-09-30: three of the four field notes that led
# to 0.7.0 were written into this repository from sessions standing in others.
rw_free_globs() {
  rw_list_globs "$1/.roadworthy/free"
}

# rw_rite <root> <key> — what the OWNER requires of this project, from .roadworthy/rites: one
# `key: value` per line, `#` comments. Empty when the file or the key is absent. The plugin's
# options are the user's and are born permissive; a project that needs more says so here, in a file
# the entry gate denies to the agent, so the requirement does not depend on anyone reading a note
# (field, 2026-10-01: a plan submitted with the pre-flight alone in a project whose written rule
# asked for a review).
#   plan_gate: preflight | review | both     what guards a plan before it is submitted
#   diff_review: required                     a closing needs an approved review of what it closes
rw_rite() {
  local root="$1" key="$2"
  [ -n "$root" ] && [ -f "$root/.roadworthy/rites" ] || return 0
  # Lower-cased, so `Diff_Review: Required` says what it looks like it says.
  tr '[:upper:]' '[:lower:]' < "$root/.roadworthy/rites" | tr -d '\r' \
    | sed -n -E "s/^[[:space:]]*${key}[[:space:]]*:[[:space:]]*([^#]*[^#[:space:]])[[:space:]]*(#.*)?\$/\\1/p" | head -1 || true
}

# rw_touched_file <session key> — where the entry gate notes the repositories a session wrote in
# other than the one it stands in, for the stop gate to answer for. The plugin's own data
# directory, never a project: the fact is about a SESSION, and the projects' local state files are
# enumerated in six places that this must not grow. Empty when the harness gave no such directory.
rw_touched_file() {
  [ -n "${CLAUDE_PLUGIN_DATA:-}" ] || return 0
  printf '%s/sessions/%s.touched' "$CLAUDE_PLUGIN_DATA" "$1"
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
