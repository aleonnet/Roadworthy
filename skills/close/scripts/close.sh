#!/usr/bin/env bash
# close.sh — run the declared gates after the last commit and record the evidence.
#
# Gates live in .roadworthy/gates, one shell command per line (`#` comments).
# Each gate is recorded in the evidence ledger as JSON:
#   {ts, head, wtree, cmd, cmd_sha256, exit, tail}
# The ledger lives in $ROADWORTHY_DATA (default: $CLAUDE_PLUGIN_DATA, else .roadworthy)
# as evidence.jsonl. A record is FRESH when its wtree equals the current content
# fingerprint, STALE otherwise, MISSING when no record exists for the command.
#
# Usage:
#   close.sh               run all gates (requires a clean tree); exit 0 = passed
#   close.sh --check       classify each gate FRESH | STALE | MISSING for the current tree
#   close.sh --needs-human "<item>"   record that a person must verify <item>; state needs_human
#   close.sh --state       print the last recorded state: passed | gaps_found | needs_human
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "close: not a git repository" >&2; exit 1; }
cd "$root" || exit 1
gates=".roadworthy/gates"
data="${ROADWORTHY_DATA:-${CLAUDE_PLUGIN_DATA:-$root/.roadworthy}}"
mkdir -p "$data"
ledger="$data/evidence.jsonl"
state_file="$data/state"
# The state is written in BOTH places. $data may point anywhere (ROADWORTHY_DATA, or the
# plugin's own directory shared by every project), and `close.sh --state` and /roadworthy:resume
# read it to decide whether a front closed cleanly -- reading another project's state and
# reporting "passed" on a front full of gaps is the failure this closes. The project copy is
# authoritative for the project; the data copy stays for whoever points ROADWORTHY_DATA at it.
project_state=".roadworthy/state"
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

record() { # cmd exit tail
  python3 - "$ledger" "$1" "$2" "$3" "$(fp)" <<'PY'
import hashlib, json, sys, time
ledger, cmd, rc, tail, fp = sys.argv[1:6]
head, wtree, state = fp.split()
with open(ledger, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "head": head, "wtree": wtree,
                         "cmd": cmd, "cmd_sha256": hashlib.sha256(cmd.encode()).hexdigest(),
                         "exit": int(rc), "tail": tail[-800:]}) + "\n")
PY
}

case "${1:-}" in
  --state) read_state; exit 0 ;;
  --needs-human)
    item="${2:?--needs-human needs an item}"
    record_state needs_human
    record "needs-human: $item" 0 "$item"
    echo "close: needs_human — $item"; exit 0 ;;
  --check)
    # No gates, or a file that declares none, is not "everything fresh": it is nothing measured.
    # Reporting success here let a night close declaring every gate FRESH with zero gates
    # (measured 2026-09-13 on this repository, which had no .roadworthy/gates at all).
    [ -f "$gates" ] || { echo "close: no $gates — a closing with no declared gate is not a closing; write the gate commands there, one per line" >&2; exit 1; }
    read -r _ wtree _ <<< "$(fp)"
    fail=0; declared=0
    while IFS= read -r cmd; do
      [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
      declared=$((declared + 1))
      status="$(python3 - "$ledger" "$cmd" "$wtree" <<'PY'
import json, sys, os
ledger, cmd, wtree = sys.argv[1:4]
last = None
if os.path.exists(ledger):
    for line in open(ledger, encoding="utf-8"):
        r = json.loads(line)
        if r["cmd"] == cmd: last = r
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
  echo "close: the tree is dirty; commit first — a gate measured before the last commit is not a gate of this closing"
  record_state gaps_found; exit 1
fi
# Measured against the SNAPSHOT taken when the front opened, never against whatever the files
# say now. Re-reading .roadworthy/gates at closing time meant editing the Verification section
# after approval silently changed what "the gates passed" proves. Projects with no snapshot
# keep the old behaviour, so nobody is blocked on upgrade.
snapshot=".roadworthy/plan.snapshot"
if [ -f "$snapshot" ]; then
  python3 - "$snapshot" "$gates" ".roadworthy/scope" <<'PY' || exit 1
import hashlib, json, os, subprocess, sys
snap_path, gates_path, scope_path = sys.argv[1:4]
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
import re
def to_regex(g):
    g = os.path.normpath(g); out = ""; i = 0
    while i < len(g):
        if g.startswith("**/", i): out += "(?:.*/)?"; i += 3
        elif g.startswith("**", i): out += ".*"; i += 2
        elif g[i] == "*": out += "[^/]*"; i += 1
        elif g[i] == "?": out += "[^/]"; i += 1
        else: out += re.escape(g[i]); i += 1
    return "^" + out + "$"
globs = [re.compile(to_regex(g)) for g in snap.get("scope_globs", [])]
base = snap.get("base_head") or ""
touched = set()
if base:
    d = subprocess.run(["git", "diff", "--name-only", base + "..HEAD"], capture_output=True, text=True)
    touched |= {l for l in d.stdout.splitlines() if l}
u = subprocess.run(["git", "ls-files", "--others", "--exclude-standard"], capture_output=True, text=True)
touched |= {l for l in u.stdout.splitlines() if l}
def local(p):
    return p.startswith(".roadworthy/")
outside = sorted(p for p in touched if not local(p) and not any(g.match(os.path.normpath(p)) for g in globs))
if outside:
    sys.stderr.write("close: the front touched %d file(s) outside its declared scope:\n" % len(outside))
    for p in outside[:20]:
        sys.stderr.write("  " + p + "\n")
    sys.stderr.write("Widen the scope in the plan and reopen the front, or leave those files alone.\n")
    sys.exit(1)
PY
fi
read -r head wtree _ <<< "$(fp)"
echo "close: HEAD $head · tree $wtree"
failed=0; ran=0
while IFS= read -r cmd; do
  [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
  ran=$((ran + 1))
  out="$(bash -c "$cmd" 2>&1)"; rc=$?
  record "$cmd" "$rc" "$out"
  if [ $rc -eq 0 ]; then printf '  OK    %s\n' "$cmd"; trivially_green "$cmd" && printf '  WARN  %s\n' "that gate cannot fail: it proves nothing"; else printf '  FAIL  %s (exit %s)\n' "$cmd" "$rc"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; failed=$((failed + 1)); fi
done < "$gates"
if [ $ran -eq 0 ]; then
  record_state gaps_found
  echo "close: $gates declares no gate; nothing was measured, so nothing passed — the scope stays locked" >&2; exit 1
fi
if [ $failed -eq 0 ]; then
  record_state passed
  rm -f .roadworthy/scope
  echo "close: passed — evidence in $ledger; scope released"
else
  record_state gaps_found
  echo "close: gaps_found — $failed gate(s) red; scope kept"; exit 1
fi
