#!/usr/bin/env bash
# scope-write.sh — open a front from an approved plan, mechanically.
#
# The first act of EXECUTION, never of planning: it reads the plan's Scope and Verification
# sections and writes, in one act,
#   .roadworthy/scope          the globs the scope lock will enforce
#   .roadworthy/gates          the commands close.sh will run, one per line
#   .roadworthy/plan.snapshot  what was approved: plan, base HEAD, globs, gates, and digests
#
# Why the snapshot. close.sh used to re-read .roadworthy/gates at closing time, so editing the
# Verification section after approval silently changed what "the gates passed" meant. The snapshot
# is taken once, at the moment the front opens, and the closing is measured against it.
#
# The digests cover `scope`, `gates` and the snapshot's own CANONICAL FORM -- the snapshot JSON
# without the `digests` field, keys sorted, no spaces. A file cannot contain its own digest; it can
# contain the digest of its canonical part.
#
# Both sections are read as FENCED BLOCKS, never as prose bullets: close.sh executes each gate line
# with `bash -c`, and `- \`cmd\` → expected result` is not a command. One grammar, and it is the one
# the machine can run. Since 0.7.0 it lives in hooks/planblocks.py, which the entry gate reads too.
#
# REOPENING a front keeps its base. The base HEAD is what close.sh measures the front's diff
# against, so taking it from the current HEAD is right when a front OPENS and wrong when one is
# reopened mid-flight -- which happens whenever an execution decision changes the plan's
# Verification block. Measured on 2026-09-14: reopening after 23 commits would have set the base
# to the tip and left the out-of-scope check with an empty diff to look at, silently. Until 0.7.0
# that depended on whoever reopened remembering `--base`; now the SAME front reopened (the plan of
# the live snapshot, by name) keeps the snapshot's base by itself, and a `--base` that disagrees is
# refused: moving the base moves what the closing looks at (field note, 2026-09-18).
#
# ONE FRONT AT A TIME. With a scope the rite wrote still on disk, opening a front from ANOTHER plan
# is refused, naming the live one. A live scope is a front that did not close; writing a new scope
# over it is how the globs of a finished-but-unclosed front were silently replaced. The way out is
# always open: close it (close.sh), or abandon it with its reason (close.sh --abandon "<reason>").
#
# The snapshot also carries, from 0.7.0: the plan's FINGERPRINT (hooks/planblocks.py: its scope,
# gates and declared base -- what an approval approves, and what the entry gate looks up before it
# lets the agent run this script); the `report:` line of the plan, the reporting form agreed for
# the front; and what was ALREADY changed outside the scope when the front opened, so the fence
# that measures the tree against the scope does not charge the front for it.
#
# Usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>]
set -euo pipefail
plan="${1:?usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>]}"; shift || true
root=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    --base) base="${2:?--base needs a ref}"; shift 2 ;;
    *) echo "scope-write: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -f "$plan" ] || { echo "scope-write: plan not found: $plan" >&2; exit 1; }
plan="$(cd "$(dirname "$plan")" && pwd -P)/$(basename "$plan")"
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "scope-write: not a git repository; give --root" >&2; exit 1; }
# Resolved BEFORE the cd below: the script may have been named by a relative path.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$root"

python3 - "$plan" "$base" "$here/../../../hooks" <<'PY'
import hashlib, json, os, subprocess, sys, time

plan = sys.argv[1]
base_arg = sys.argv[2] if len(sys.argv) > 2 else ""
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from globmatch import matches
from planblocks import blocks, fingerprint, header

text = open(plan, encoding="utf-8").read()
globs, gates, declared_base = blocks(text)
missing = []
if globs is None: missing.append("a '## Scope' ('## Escopo') section with a fenced block")
if gates is None: missing.append("a '## Verification' ('## Verificação') section with a fenced block")
if missing:
    sys.stderr.write("scope-write: the plan is missing " + "; and ".join(missing) +
                     ".\nBoth are read as fenced blocks, never as prose: close.sh runs each gate line "
                     "with `bash -c`, and a bullet like `- `cmd` -> expected` is not a command.\n")
    sys.exit(1)
if not globs: sys.stderr.write("scope-write: the Scope block is empty; a front with no scope is not a front.\n"); sys.exit(1)
if not gates: sys.stderr.write("scope-write: the Verification block declares no gate; close.sh cannot close without one.\n"); sys.exit(1)

name = os.path.basename(plan)

def rev(ref):
    r = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"], capture_output=True, text=True)
    return r.stdout.strip() if r.returncode == 0 else ""

# The front that is live, if any: a scope the rite wrote, and the snapshot written with it.
live = None
try:
    with open(".roadworthy/scope", encoding="utf-8", errors="replace") as fh:
        rite_wrote = "Written by scope-write.sh" in fh.readline()
except Exception:
    rite_wrote = False
if rite_wrote:
    try:
        live = json.load(open(".roadworthy/plan.snapshot", encoding="utf-8"))
    except Exception:
        live = {}
if live is not None and live.get("plan_name") and live["plan_name"] != name:
    sys.stderr.write("scope-write: a second front opened over a live one is refused. A front is already open here, "
                     "from %s (since %s). One front at a time: close it (skills/close/scripts/close.sh) or abandon it "
                     "with its reason (close.sh --abandon \"<reason>\"), then open this one.\n"
                     % (live["plan_name"], live.get("ts", "an unknown time")))
    sys.exit(1)

if live and live.get("base_head"):
    # The same front, reopened: its base is the one it opened with.
    head = live["base_head"]
    if base_arg and rev(base_arg) != head:
        sys.stderr.write("scope-write: this front opened at %s and --base %s is another commit. Reopening keeps the base: "
                         "it is what the closing measures the front's diff against. Drop --base, or abandon the front "
                         "(close.sh --abandon \"<reason>\") and open a new one.\n" % (head[:12], base_arg))
        sys.exit(1)
    reopened = True
else:
    # A NEW front: the base is the one named, else the tip.
    wanted = base_arg if base_arg else "HEAD"
    head = rev(wanted)
    if not head:
        sys.stderr.write("scope-write: base %s does not resolve to a commit here.\n" % wanted); sys.exit(1)
    reopened = False

os.makedirs(".roadworthy", exist_ok=True)
banner = (f"# Written by scope-write.sh from {name}. Do not edit by hand: the closing is measured\n"
          f"# against .roadworthy/plan.snapshot, and a hand edit here only makes the digests disagree.\n")
with open(".roadworthy/scope", "w", encoding="utf-8") as fh:
    fh.write(banner + "\n".join(globs) + "\n")
with open(".roadworthy/gates", "w", encoding="utf-8") as fh:
    fh.write(banner + "\n".join(gates) + "\n")

def sha(path):
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()
    except Exception:
        return ""

# What is already changed outside the scope, with its content: it was there before this front, and
# the fence that measures the tree against the scope (hooks/frontcheck.py) leaves it alone until
# it changes again. A reopened front keeps the list it opened with.
if reopened and isinstance(live.get("preexisting"), dict):
    preexisting = live["preexisting"]
else:
    preexisting = {}
    st = subprocess.run(["git", "status", "--porcelain", "-z", "-uall"], capture_output=True)
    entries = st.stdout.decode("utf-8", errors="replace").split("\0") if st.returncode == 0 else []
    i = 0
    while i < len(entries):
        e = entries[i]; i += 1
        if len(e) < 4:
            continue
        paths = [e[3:]]
        if e[0] in "RC" and i < len(entries):
            paths.append(entries[i]); i += 1
        for p in paths:
            if not p.startswith(".roadworthy/") and not matches(p, globs):
                preexisting[p] = sha(p)

snap = {"ts": live["ts"] if reopened and live.get("ts") else time.strftime("%Y-%m-%dT%H:%M:%S"),
        "plan": os.path.abspath(plan), "plan_name": name,
        "base_head": head, "scope_globs": globs, "gates": gates,
        "declared_base": declared_base, "fingerprint": fingerprint(text),
        "report": header(text, "report|relato"), "preexisting": preexisting}
canonical = json.dumps(snap, sort_keys=True, separators=(",", ":"))
snap["digests"] = {"scope": sha(".roadworthy/scope"),
                   "gates": sha(".roadworthy/gates"),
                   "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
with open(".roadworthy/plan.snapshot", "w", encoding="utf-8") as fh:
    json.dump(snap, fh, indent=1, ensure_ascii=False)
    fh.write("\n")

# The rite's local state is not content. A project that does not ignore it commits the scope and
# the snapshot with the first `git add -A`, and from then on a `git stash` or a `git checkout .`
# brings an OLD scope back in silence (found by the simulation of honest work, 2026-10-01). So
# what is not ignored yet is ignored here, in the repository's own exclude file -- local to this
# clone, never a change to the project. What is already TRACKED cannot be fixed that way; it is said.
LOCAL = ["scope", "state", "plan.snapshot", "overnight", "evidence.jsonl", "denials.jsonl",
         "refutations.jsonl", "preflight.jsonl", "readings.jsonl", "stop-latch/"]
tracked = [l for l in subprocess.run(["git", "ls-files", "--"] + [".roadworthy/" + n.rstrip("/") for n in LOCAL],
                                     capture_output=True, text=True).stdout.splitlines() if l]
loose = [n for n in LOCAL if ".roadworthy/" + n.rstrip("/") not in tracked and
         subprocess.run(["git", "check-ignore", "-q", ".roadworthy/" + n.rstrip("/")]).returncode != 0]
if loose:
    try:
        ex = subprocess.run(["git", "rev-parse", "--git-path", "info/exclude"], capture_output=True, text=True).stdout.strip()
        os.makedirs(os.path.dirname(ex), exist_ok=True)
        with open(ex, "a", encoding="utf-8") as fh:
            fh.write("# Roadworthy: the rite's local state (written by scope-write.sh)\n" +
                     "".join(".roadworthy/%s\n" % n for n in loose))
    except Exception:
        pass

print(f"scope-write: front {'reopened' if reopened else 'open'} from {name}")
print(f"  base HEAD  {head[:12] or '(no commits)'}{'  (kept from when the front opened)' if reopened else ''}")
print(f"  scope      {len(globs)} glob(s) -> .roadworthy/scope")
print(f"  gates      {len(gates)} command(s) -> .roadworthy/gates")
print(f"  snapshot   .roadworthy/plan.snapshot")
if snap["report"]:
    print(f"  report     {snap['report']}")
if preexisting:
    print(f"  note       {len(preexisting)} path(s) outside the scope were already changed when the front opened; they are not this front's")
if tracked:
    print(f"  warning    the rite's local state is TRACKED by git here ({', '.join(tracked)}): a stash or a checkout will bring an old scope back. Untrack it: git rm --cached {' '.join(tracked)}")
PY
