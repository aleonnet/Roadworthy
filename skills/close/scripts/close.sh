#!/usr/bin/env bash
# close.sh — run the declared gates after the last commit and record the evidence.
#
# Gates live in .roadworthy/gates, one shell command per line (`#` comments).
# Each gate is recorded in the evidence ledger as JSON:
#   {ts, head, wtree, cmd, cmd_sha256, exit, tail}
# The ledger lives in $ROADWORTHY_DATA when that is set, else in the project's .roadworthy, as
# evidence.jsonl -- the same rule as rw_data_dir in hooks/lib.sh, repeated here because this script
# runs on its own. CLAUDE_PLUGIN_DATA is NOT in the chain: Claude Code sets it for every hook to a
# directory that is per plugin and shared by every project, and a shell run by a person does not
# set it, so a ledger written under it is one the person's `--check` never finds and the hook's
# `--check` never finds the person's (measured 2026-09-14: six FRESH gates reported MISSING).
# A record is FRESH when its wtree equals the current content fingerprint, STALE otherwise,
# MISSING when no record exists for the command.
#
# EVERY DECLARED GATE RUNS, OR THE CLOSING REFUSES (0.7.0). Until then the loop read the gates file
# through its standard input and every gate inherited it: a gate that reads stdin -- an `ssh`, a
# `cat` with no argument -- consumed the lines after it, the loop met end of file with nothing
# failed, and the front closed `passed` with gates that never ran (field, 2026-09-24: nine
# declared, seven run). The list is read through its own descriptor now, each gate gets an empty
# standard input, and the number that ran must equal the number declared.
#
# THE EVIDENCE OF A GATE DOES NOT DEPEND ON HOW MUCH IT PRINTS (0.7.0). The whole output used to
# travel to python3 as an ARGUMENT; above the system's limit the record was never written, the
# screen said OK and the next --check said MISSING (field, 2026-09-22, a suite of 3,896 tests:
# `python3: Argument list too long`). The output goes to a file and the record reads its tail.
#
# HUMAN VERIFICATION HAS A STATE OF ITS OWN (0.7.0). The state was one word, rewritten by every
# closing, so a later front erased what an earlier one left for a person to check, and there was no
# way to record the answer (field, 2026-09-30). The items live in the evidence ledger, which has
# always recorded them and was never read back: `--needs-human` opens one, `--human` closes it with
# who checked, and the state is derived -- `needs_human` while any is open, whatever closed since.
#
# Refuted 2026-09-14, against tests/scripts/close.sh: the ledger resolved through CLAUDE_PLUGIN_DATA
# again -> red with `close.sh looked for the ledger in the shared plugin directory`; the orphan
# check removed from the closing -> red with `an orphan scope closed the front`; removed from
# --check -> red with `an orphan scope passed --check`. Each green again on the clean file,
# restored with its SHA-256 verified (skills/refute/scripts/refute.sh).
# Refuted 2026-09-30 (0.7.0), same case: the gate handed the list as its standard input -> red with
# `a gate that reads stdin hid the gates after it`; the output passed as an argument again -> red
# with `a large gate output left no evidence`; the declared-against-ran comparison removed -> red
# with `the closing passed with gates that never ran`; the derived state ignoring open items -> red
# with `a later closing erased the pending human verification`. Each green again on the clean file.
#
# Usage:
#   close.sh               run all gates (requires a clean tree); exit 0 = passed
#   close.sh --check       classify each gate FRESH | STALE | MISSING for the current tree
#   close.sh --state       print the state: passed | gaps_found | needs_human | none
#   close.sh --needs-human "<item>"                 a person must verify <item>
#   close.sh --human                                list what is waiting for a person
#   close.sh --human "<item>|<id>|all" approved|rejected --by <who> [--note "<text>"]
#   close.sh --abandon "<reason>"                   release a front that will not close, on the record
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "close: not a git repository" >&2; exit 1; }
cd "$root" || exit 1
gates=".roadworthy/gates"
snapshot=".roadworthy/plan.snapshot"
data="${ROADWORTHY_DATA:-$root/.roadworthy}"
mkdir -p "$data"
ledger="$data/evidence.jsonl"
state_file="$data/state"
# The state is written in BOTH places. $data may point anywhere through ROADWORTHY_DATA, and
# `close.sh --state` and /roadworthy:resume read it to decide whether a front closed cleanly --
# reading another project's state and reporting "passed" on a front full of gaps is the failure
# this closes. The project copy is authoritative for the project; the data copy stays for whoever
# points ROADWORTHY_DATA at it.
project_state=".roadworthy/state"
# A scope the rite wrote names its plan in its first line, and the rite writes the snapshot in the
# same act. That scope with no snapshot is not an old project: it is the snapshot removed after
# the front opened -- the one act that used to make this script skip everything it measures
# against (digests, and the files the front touched outside its globs). A scope written by hand
# carries no banner and keeps the old path: toy repositories, evaluation scaffolds and projects
# from before 0.6.0 open their fronts that way, and refusing them would put an agent in front of
# a wall it cannot resolve.
rite_scope_orphan() {
  [ -f .roadworthy/scope ] && head -1 .roadworthy/scope | grep -q 'Written by scope-write.sh' && [ ! -f "$snapshot" ]
}
orphan_refusal="close: .roadworthy/scope was written by the rite and $snapshot is gone. The closing is measured against the snapshot, and a front cannot lose it and still close: reopen the front from the plan (skills/plan/scripts/scope-write.sh <plan.md>), which writes the snapshot again from what was approved."
record_state() {  # record_state <passed|gaps_found|needs_human>
  mkdir -p "$(dirname "$state_file")" ".roadworthy" 2>/dev/null || true
  printf '%s\n' "$1" > "$state_file"
  [ "$(cd "$(dirname "$state_file")" && pwd -P)/$(basename "$state_file")" = "$(cd .roadworthy && pwd -P)/state" ] \
    || printf '%s\n' "$1" > "$project_state"
}
# Reading follows the same order: the project first, the shared data only as a fallback.
read_state() {
  if [ -f "$project_state" ]; then cat "$project_state"
  elif [ -f "$state_file" ]; then cat "$state_file"
  else echo "none"; fi
}
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fp() { bash "$here/tree-fingerprint.sh" "$root"; }
front_name() {
  [ -f "$snapshot" ] || return 0
  python3 -c 'import json,sys
try: print(json.load(open(sys.argv[1])).get("plan_name", ""))
except Exception: print("")' "$snapshot" 2>/dev/null || true
}
# A gate that cannot go red is a green light, not a measurement. This is a NAMED enumeration and
# it never closes, so it warns and never refuses -- what defends the closing is that every gate
# has to come from the plan. Silence, though, is how "every gate FRESH" gets written under a
# file containing the single word `true`.
trivially_green() {
  case "$(printf '%s' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')" in
    true|:|"bash -c true"|"sh -c true"|"test 1 = 1"|"[ 1 = 1 ]"|"python3 -c pass"|"python -c pass"|"exit 0") return 0 ;;
    *) return 1 ;;
  esac
}

record() { # record <cmd> <exit> <file holding the gate's output>
  python3 - "$ledger" "$1" "$2" "$3" "$(fp)" <<'PY'
import hashlib, json, os, sys, time
ledger, cmd, rc, out_file, fp = sys.argv[1:6]
head, wtree, state = fp.split()
tail = ""
# The TAIL of the file, never the whole of it: a gate may print megabytes, and only the last
# lines say how it ended.
if out_file and os.path.exists(out_file):
    with open(out_file, "rb") as fh:
        fh.seek(0, 2)
        fh.seek(max(0, fh.tell() - 4000))
        tail = fh.read().decode("utf-8", errors="replace")[-800:]
with open(ledger, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "head": head, "wtree": wtree,
                         "cmd": cmd, "cmd_sha256": hashlib.sha256(cmd.encode()).hexdigest(),
                         "exit": int(rc), "tail": tail}) + "\n")
PY
}

# Everything in the ledger that is not a gate: the items waiting for a person, the verdicts, and
# how each closing ended. One reader and one writer, so the state is DERIVED from what happened
# instead of being the last word somebody wrote.
#   rw_ledger state                                   -> the derived state, or empty when the
#                                                        ledger says nothing (the state file decides)
#   rw_ledger open                                    -> one line per open item: id TAB item TAB ts TAB front
#   rw_ledger add-open <item> <front>                 -> a person must verify <item>
#   rw_ledger verdict <item|id|all> <approved|rejected> <by> <note>   exit 3: nothing matched
#   rw_ledger close <passed|gaps_found|abandoned> <front> <reason>
rw_ledger() {
  python3 - "$ledger" "$root" "$(fp)" "$@" <<'PY'
import hashlib, json, os, sys, time
ledger, root, fp, op = sys.argv[1], os.path.realpath(sys.argv[2]), sys.argv[3], sys.argv[4]
args = sys.argv[5:]
# A ledger inside the project belongs to the project, whatever path the project has today. Only a
# ledger that lives elsewhere (ROADWORTHY_DATA) can hold the records of several projects.
shared = os.path.realpath(os.path.dirname(ledger)) != os.path.join(root, ".roadworthy")
head, wtree = (fp.split() + ["", ""])[:2]

def records():
    out = []
    if os.path.exists(ledger):
        for line in open(ledger, encoding="utf-8", errors="replace"):
            try:
                out.append(json.loads(line))
            except Exception:
                continue
    return out

def mine(r):
    # In the project's own ledger every record is the project's: filtering by path there would
    # drop the pending items of a repository the day its directory is renamed. In a shared ledger
    # a record that names a root belongs to that root; one written by 0.6.2 names none and belongs
    # to whoever reads it.
    if not shared:
        return True
    return not r.get("root") or os.path.realpath(r["root"]) == root

def item_id(text):
    # The identity of an item is its text: said twice, it is one item, and a record of 0.6.2
    # (no id at all) is the same item as the one a later command names.
    return hashlib.sha256(" ".join(text.split()).encode()).hexdigest()[:8]

def fold():
    # `gates` is how the LAST run of gates ended, for a ledger with no closing on record: the gate
    # records that share the tree of the last one. 0.6.2 wrote those and nothing else.
    open_items, outcome, rejected, asked, gates = {}, "", False, False, []
    for r in records():
        if not mine(r):
            continue
        kind, cmd = r.get("kind", ""), r.get("cmd", "")
        if kind == "needs-human" or (not kind and cmd.startswith("needs-human: ")):
            item = r.get("item") or cmd[len("needs-human: "):]
            open_items.setdefault(item_id(item), (item, r.get("ts", ""), r.get("front", "")))
            asked = True
        elif not kind:
            if gates and gates[-1].get("wtree") != r.get("wtree"):
                gates = []
            gates.append(r)
        elif kind == "human":
            open_items.pop(item_id(r.get("item", "")), None)
            if r.get("verdict") == "rejected":
                rejected = True
        elif kind == "close":
            outcome = r.get("outcome", "")
            if outcome == "passed":
                rejected = False        # the work was redone and its gates passed again
    if not outcome and asked:
        # Somebody was asked, every answer is in, and no closing is on record: a project from
        # before 0.7.0, whose state file still holds the `needs_human` this ledger replaced.
        # Saying nothing would leave that word standing with nothing open.
        outcome = "gaps_found" if any(g.get("exit") for g in gates) else ("passed" if gates else "none")
    return open_items, outcome, rejected

def append(rec):
    rec = dict({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "head": head, "wtree": wtree,
                "root": root, "exit": 0}, **rec)
    rec["cmd_sha256"] = hashlib.sha256(rec["cmd"].encode()).hexdigest()
    with open(ledger, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")

if op == "state":
    open_items, outcome, rejected = fold()
    if open_items:
        print("needs_human")
    elif rejected:
        print("gaps_found")
    elif outcome:
        print(outcome if outcome in ("passed", "none") else "gaps_found")
elif op == "open":
    for iid, (item, ts, front) in fold()[0].items():
        print("\t".join((iid, item, ts, front)))
elif op == "add-open":
    item, front = args[0], args[1]
    append({"kind": "needs-human", "cmd": "needs-human: " + item, "item": item, "id": item_id(item),
            "front": front, "tail": item})
elif op == "verdict":
    which, verdict, by, note = args[0], args[1], args[2], args[3]
    open_items = fold()[0]
    if which == "all":
        targets = list(open_items.items())
    else:
        targets = [(i, v) for i, v in open_items.items() if which in (i, v[0]) or item_id(which) == i]
    if not targets:
        sys.exit(3)
    for iid, (item, _, front) in targets:
        append({"kind": "human", "cmd": "human: %s %s" % (item, verdict), "item": item, "id": iid,
                "verdict": verdict, "by": by, "note": note, "front": front, "tail": note})
elif op == "close":
    outcome, front, reason = args[0], args[1], args[2]
    append({"kind": "close", "cmd": "close: " + outcome, "outcome": outcome, "front": front,
            "reason": reason, "tail": reason})
PY
}
# The state the ledger derives, written where the fences and the next session read it. When the
# ledger says nothing at all -- a project from before 0.7.0 -- the recorded word stands.
sync_state() {
  local derived
  derived="$(rw_ledger state)"
  [ -n "$derived" ] && record_state "$derived"
  return 0
}
current_state() {
  local derived
  derived="$(rw_ledger state)"
  if [ -n "$derived" ]; then printf '%s\n' "$derived"; else read_state; fi
}
end_closing() {  # end_closing <passed|gaps_found|abandoned> [reason]
  rw_ledger close "$1" "$(front_name)" "${2:-}"
  sync_state
}
print_open_human() {  # prints the open items, indented; returns 1 when there are none
  local lines
  lines="$(rw_ledger open)"
  [ -n "$lines" ] || return 1
  printf '%s\n' "$lines" | while IFS=$'\t' read -r id item ts front; do
    printf '  %s  %s  (since %s%s)\n' "$id" "$item" "$ts" "${front:+, front $front}"
  done
}

case "${1:-}" in
  --state) current_state; exit 0 ;;
  --needs-human)
    item="${2:?--needs-human needs an item}"
    rw_ledger add-open "$item" "$(front_name)"
    sync_state
    echo "close: needs_human — $item"; exit 0 ;;
  --human)
    if [ $# -eq 1 ]; then
      print_open_human || echo "close: no human verification is open"
      exit 0
    fi
    which="$2"; verdict="${3:-}"; by=""; note=""
    shift 3 2>/dev/null || shift $#
    while [ $# -gt 0 ]; do
      case "$1" in
        # One shift, then another only if there is something left: `shift 2` with a single
        # argument fails, shifts nothing, and the loop never ends.
        --by) by="${2:-}"; shift; [ $# -eq 0 ] || shift ;;
        --note) note="${2:-}"; shift; [ $# -eq 0 ] || shift ;;
        *) echo "close: unknown argument $1" >&2; exit 1 ;;
      esac
    done
    case "$verdict" in approved|rejected) ;; *) echo "close: the verdict is 'approved' or 'rejected' (close.sh --human \"<item>\" approved --by <who>)" >&2; exit 1 ;; esac
    [ -n "$by" ] || { echo "close: a verdict names who checked (--by <who>): an answer with nobody behind it is the sentence this command replaces" >&2; exit 1; }
    rw_ledger verdict "$which" "$verdict" "$by" "$note"; rc=$?
    if [ "$rc" -eq 3 ]; then
      echo "close: no open item matches '$which'. Open items:" >&2
      print_open_human >&2 || echo "  (none)" >&2
      exit 1
    fi
    [ "$rc" -eq 0 ] || exit 1
    sync_state
    echo "close: $verdict by $by — state $(current_state)"
    print_open_human || true
    exit 0 ;;
  --abandon)
    reason="${2:-}"
    [ -n "$reason" ] || { echo "close: abandoning a front needs a reason (close.sh --abandon \"<reason>\"): it is recorded, and the next session reads it" >&2; exit 1; }
    [ -f .roadworthy/scope ] || { echo "close: no front is open here; there is nothing to abandon" >&2; exit 1; }
    end_closing abandoned "$reason"
    rm -f .roadworthy/scope
    echo "close: front abandoned — $reason. State gaps_found; scope released. What it left in the tree is still there: say so in the hand-off."
    exit 0 ;;
  --check)
    # No gates, or a file that declares none, is not "everything fresh": it is nothing measured.
    # Reporting success here let a night close declaring every gate FRESH with zero gates
    # (measured 2026-09-13 on this repository, which had no .roadworthy/gates at all).
    [ -f "$gates" ] || { echo "close: no $gates — a closing with no declared gate is not a closing; write the gate commands there, one per line" >&2; exit 1; }
    if rite_scope_orphan; then echo "$orphan_refusal" >&2; exit 1; fi
    read -r _ wtree _ <<< "$(fp)"
    fail=0; declared=0
    # `|| [ -n "$cmd" ]`: a last line with no newline is still a line. `read` returns non-zero on
    # it, and without this the gate it holds is dropped -- here, in the count and in the run.
    while IFS= read -r cmd || [ -n "$cmd" ]; do
      [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
      declared=$((declared + 1))
      status="$(python3 - "$ledger" "$cmd" "$wtree" <<'PY'
import json, sys, os
ledger, cmd, wtree = sys.argv[1:4]
last = None
if os.path.exists(ledger):
    for line in open(ledger, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        if r.get("cmd") == cmd and not r.get("kind"): last = r
if last is None: print("MISSING")
elif last["wtree"] == wtree and last["exit"] == 0: print("FRESH")
elif last["wtree"] == wtree: print("FRESH-RED")
else: print("STALE")
PY
)"
      printf '  %-9s %s\n' "$status" "$cmd"
      trivially_green "$cmd" && printf '  %-9s %s\n' "WARN" "that gate cannot fail: it proves nothing"
      [ "$status" = "FRESH" ] || fail=1
    done < "$gates"
    [ "$declared" -gt 0 ] || { echo "close: $gates declares no gate (only blank lines or comments); nothing was measured" >&2; exit 1; }
    exit $fail ;;
  "") ;;
  *) echo "close: unknown argument $1" >&2; exit 1 ;;
esac

[ -f "$gates" ] || { echo "close: no $gates — declare the gates first"; exit 1; }
# The dirty check ignores the plugin's OWN transient state, the same list tree-fingerprint.sh
# leaves out of the fingerprint. Without this, writing the recorded state dirties the tree of
# any project that has not gitignored it yet, and the next closing refuses -- the plugin would
# block itself with a file it wrote.
rw_dirty() {
  git status --porcelain | grep -v -E ' \.roadworthy/(scope|state|plan\.snapshot|overnight|evidence\.jsonl|denials\.jsonl|refutations\.jsonl|preflight\.jsonl|readings\.jsonl|stop-latch/)'
}
if [ -n "$(rw_dirty)" ]; then
  echo "close: the tree is dirty; commit first — a gate measured before the last commit is not a gate of this closing. What is not this front's (a file of the owner, of another session) is set aside for the closing with 'git stash push -u -- <path>' and brought back after it with 'git stash pop'."
  end_closing gaps_found "dirty tree"; exit 1
fi
# Measured against the SNAPSHOT taken when the front opened, never against whatever the files
# say now. Re-reading .roadworthy/gates at closing time meant editing the Verification section
# after approval silently changed what "the gates passed" proves. A front the rite opened cannot
# close without its snapshot (rite_scope_orphan, above); a scope written by hand has no snapshot
# to measure against and keeps the pre-0.6.0 path.
if rite_scope_orphan; then
  echo "$orphan_refusal" >&2
  end_closing gaps_found "the snapshot is gone"; exit 1
fi
# The snapshot of a front, and no scope: that front already ended (it closed, or it was
# abandoned), and there is nothing open to close. Said as what it is -- until 0.7.0 this fell into
# the digest check below and answered "the scope changed since the front opened", to an agent that
# had only committed its hand-off after a green closing. The state is left as it was.
if [ -f "$snapshot" ] && [ ! -f .roadworthy/scope ]; then
  echo "close: no front is open here — the last one ($(front_name)) already ended as '$(current_state)'. To measure the gates again on this tree, reopen it from the same plan (skills/plan/scripts/scope-write.sh <plan.md>) and close it. A hand-off written after the closing is the usual reason: write and commit it BEFORE closing next time, and the closing measures the tree that ships." >&2
  exit 1
fi
if [ -f "$snapshot" ]; then
  # A refusal here is how the closing ENDED, and the state says so: `--state` used to keep the
  # word of the front before (`passed`), or `none`, after a closing that had refused.
  python3 - "$snapshot" "$gates" ".roadworthy/scope" "$here/../../../hooks" <<'PY' || { end_closing gaps_found "refused before the gates: the foundation, the scope or a protected path"; exit 1; }
import hashlib, json, os, subprocess, sys
snap_path, gates_path, scope_path, hooks_dir = sys.argv[1:5]
sys.dont_write_bytecode = True   # a __pycache__ under hooks/ would be a stray file to this very check
sys.path.insert(0, hooks_dir)
from globmatch import matches
snap = json.load(open(snap_path, encoding="utf-8"))
declared = snap.get("digests") or {}

def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest() if os.path.exists(path) else ""

bare = {k: v for k, v in snap.items() if k != "digests"}
canonical = json.dumps(bare, sort_keys=True, separators=(",", ":"))
now = {"scope": sha(scope_path), "gates": sha(gates_path),
       "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
for k in ("scope", "gates", "snapshot_canonical"):
    if declared.get(k) and declared[k] != now[k]:
        what = {"scope": scope_path, "gates": gates_path, "snapshot_canonical": snap_path}[k]
        sys.stderr.write(f"close: {what} changed since the front opened.\n"
                         f"  approved {declared[k][:16]}\n  now      {now[k][:16]}\n"
                         "The closing is measured against what was approved. Reopen the front from the\n"
                         "plan (scope-write.sh) instead of editing the foundation by hand.\n")
        sys.exit(1)

# Every file the front touched has to be inside the declared globs. A write through the shell
# never passes the scope lock -- this is where that gets caught, after the fact but before the
# front can call itself closed. The plugin's own transient state is excluded: it is written BY
# the closing, so requiring it to be in scope would stop every front from ever closing. The
# whole of .roadworthy/ is excluded, not just the transient part: the rite writes `gates` when
# the front opens, and demanding that every plan declare the plugin's own bookkeeping in its
# scope would put housekeeping in every Scope section. A front whose SUBJECT is one of those
# files still declares it -- the exclusion only stops the closing from refusing over them.
# The glob grammar is hooks/globmatch.py, the same file the scope lock reads: "outside the
# declared globs" has to mean here exactly what it meant to the lock that denied the edit.
globs = snap.get("scope_globs", [])
base = snap.get("base_head") or ""
# What THIS front changed: hooks/frontcheck.py answers it for the entry gate and for the closing
# alike -- the difference between the base and HEAD, restricted to the commits made here. A
# commit that arrived by a pull or a merge of the upstream is somebody else's and is not counted;
# names are read NUL-separated, so one with a non-ASCII character is the name the globs see.
from frontcheck import front_paths
touched = set(front_paths(os.getcwd(), base))
u = subprocess.run(["git", "ls-files", "--others", "--exclude-standard", "-z"], capture_output=True)
touched |= {l for l in u.stdout.decode("utf-8", errors="replace").split("\0") if l}
# The plan of THIS front is the rite's own artefact: when it lives inside the repository (the
# `plans` directory of docs.json, the house norm's home for it) it is written before the front
# exists and cannot be in its own scope. The snapshot names it.
own_plan = ""
try:
    own_plan = os.path.relpath(os.path.realpath(snap.get("plan") or ""), os.path.realpath(os.getcwd()))
except Exception:
    own_plan = ""
def listed(path):
    try:
        return [l.strip() for l in open(path, encoding="utf-8", errors="replace") if l.strip() and not l.strip().startswith("#")]
    except Exception:
        return []
# What needs no scope, the same three things the commit guard lets through (hooks/guard-commit):
# the rite's own files, a plan kept in the project's plans directory -- this front's and the
# hand-off written while it was open -- and what the owner declared outside the rite.
free = listed(".roadworthy/free")
plans_home = ""
try:
    plans_home = (json.load(open(".roadworthy/docs.json")).get("plans") or "").rstrip("/")
except Exception:
    plans_home = ""
def local(p):
    if p.startswith(".roadworthy/") or (own_plan and os.path.normpath(p) == own_plan):
        return True
    if plans_home and plans_home != "." and p.endswith(".md") and os.path.dirname(os.path.normpath(p)) == os.path.normpath(plans_home):
        return True
    return bool(free) and matches(p, free)
# A protected path in the front's diff: the fences deny it at the edit, at the shell and at the
# commit, and the closing is the last place to say so. Until 0.7.0 it did not look.
protected = listed(".roadworthy/protected")
hit = sorted(p for p in touched if protected and matches(p, protected))
if hit:
    sys.stderr.write("close: the front changed %d protected path(s) (.roadworthy/protected):\n" % len(hit))
    for p in hit[:20]:
        sys.stderr.write("  " + p + "\n")
    sys.stderr.write("A protected path is off limits to the front: put it back as it was at the base, and report the change you needed.\n")
    sys.exit(1)
outside = sorted(p for p in touched if not local(p) and not matches(p, globs))
if outside:
    sys.stderr.write("close: the front touched %d file(s) outside its declared scope:\n" % len(outside))
    for p in outside[:20]:
        sys.stderr.write("  " + p + "\n")
    sys.stderr.write("Leave those files as they were at the base, or take the change to the plan: edit its Scope\n"
                     "block, submit it again for approval, and run scope-write.sh on the same plan (it reopens\n"
                     "this front and keeps its base).\n")
    sys.exit(1)
PY
fi
read -r head wtree _ <<< "$(fp)"
echo "close: HEAD $head · tree $wtree"
# How many gates the file DECLARES, counted before any of them runs: the same count --check makes.
declared_n=0
while IFS= read -r cmd || [ -n "$cmd" ]; do
  [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
  declared_n=$((declared_n + 1))
done < "$gates"
gate_out="$(mktemp)"
trap 'rm -f "$gate_out"' EXIT
failed=0; ran=0
# The list is read through descriptor 3, and each gate runs with an EMPTY standard input and
# without that descriptor: whatever a gate reads, it is never the list of the gates after it.
exec 3< "$gates"
while IFS= read -r cmd <&3 || [ -n "$cmd" ]; do
  [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
  ran=$((ran + 1))
  bash -c "$cmd" < /dev/null > "$gate_out" 2>&1 3<&-; rc=$?
  record "$cmd" "$rc" "$gate_out"
  if [ $rc -eq 0 ]; then printf '  OK    %s\n' "$cmd"; trivially_green "$cmd" && printf '  WARN  %s\n' "that gate cannot fail: it proves nothing"; else printf '  FAIL  %s (exit %s)\n' "$cmd" "$rc"; tail -5 "$gate_out" | sed 's/^/        /'; failed=$((failed + 1)); fi
done
exec 3<&-
if [ $ran -eq 0 ]; then
  end_closing gaps_found "no gate declared"
  echo "close: $gates declares no gate; nothing was measured, so nothing passed — the scope stays locked" >&2; exit 1
fi
# Whatever makes the loop stop early -- a gate that empties the list, a descriptor closed under
# it -- the count has to agree. A closing that ran fewer gates than it declared measured less
# than it claims.
if [ "$ran" -ne "$declared_n" ]; then
  end_closing gaps_found "$declared_n gates declared, $ran ran"
  echo "close: gaps_found — $declared_n gate(s) declared, $ran ran. A gate that did not run did not pass; the scope stays locked." >&2; exit 1
fi
# What the OWNER requires of a closing here (.roadworthy/rites): `diff_review: required` means the
# front only passes with a reviewer's APPROVED verdict about the very commit being closed. The
# verdict is the one hooks/review-record wrote when the reviewer finished -- a record with a source
# that is not the agent describing its own review. Changing anything after the review means
# reviewing again: the record names the commit.
# Read lower-cased; a word it does not know is refused, never read as "no requirement" (the
# adversarial simulation of 2026-10-01 closed a front with `diff_review: Required` in the rites).
diff_review=""
if [ -f .roadworthy/rites ]; then
  diff_review="$(tr '[:upper:]' '[:lower:]' < .roadworthy/rites | tr -d '\r' | sed -n -E 's/^[[:space:]]*diff_review[[:space:]]*:[[:space:]]*([^#[:space:]]+).*/\1/p' | head -1 || true)"
fi
if [ -n "$diff_review" ] && [ "$diff_review" != "required" ]; then
  end_closing gaps_found "the rites say diff_review: $diff_review"
  echo "close: gaps_found — .roadworthy/rites says diff_review is '$diff_review'; the only word it knows is 'required'. That file is the owner's: report it. The scope is kept." >&2; exit 1
fi
if [ $failed -eq 0 ] && [ "$diff_review" = "required" ]; then
  review="$(python3 - "$ledger" "$head" <<'PY'
import json, os, sys
ledger, head = sys.argv[1], sys.argv[2]
last = None
if os.path.exists(ledger):
    for line in open(ledger, encoding="utf-8", errors="replace"):
        try:
            r = json.loads(line)
        except Exception:
            continue
        # A verdict counts when the reviewer of this plugin gave it: any subagent can be told to
        # end with the line, and the main agent would be writing its own review through it.
        # (No apostrophe in this block: bash counts quotes while scanning the substitution.)
        if r.get("kind") == "review" and r.get("head") == head and "cold-reviewer" in (r.get("agent") or ""):
            last = r
print((last or {}).get("verdict", "NONE"))
PY
)"
  if [ "$review" != "APPROVED" ]; then
    end_closing gaps_found "diff review required: $review for $head"
    if [ "$review" = "NONE" ]; then
      echo "close: gaps_found — the gates passed, and this project requires a review of the diff (.roadworthy/rites: diff_review: required). No reviewer's verdict is on record for $head. Run the cold reviewer on the front's diff (it ends with a VERDICT line, which the plugin records), then close again; the scope is kept." >&2
    else
      echo "close: gaps_found — the gates passed, and the last review of $head says $review (.roadworthy/rites: diff_review: required). Fix what it found, commit, review again, then close; the scope is kept." >&2
    fi
    exit 1
  fi
  echo "  OK    diff review: APPROVED for $head (required by .roadworthy/rites)"
fi
if [ $failed -eq 0 ]; then
  end_closing passed
  rm -f .roadworthy/scope
  echo "close: passed — evidence in $ledger; scope released"
  if open_now="$(print_open_human)"; then
    echo "close: the gates passed and a person still has to check what is below — the state is needs_human until the answer is recorded (close.sh --human \"<item>\" approved|rejected --by <who>):"
    printf '%s\n' "$open_now"
  fi
else
  end_closing gaps_found "$failed gate(s) red"
  echo "close: gaps_found — $failed gate(s) red; scope kept"; exit 1
fi
