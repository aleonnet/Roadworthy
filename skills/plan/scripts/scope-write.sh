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
# WHO OPENS IT. The agent opens a front from an approval on record: the entry gate looks it up
# before it lets the agent run this script, and every write afterwards asks for it again
# (hooks/frontcheck.py). The OWNER opens one himself, in a shell of his own, by saying so:
# `--owner` is written in the snapshot and stands where the approval would. It is a person's act --
# the entry gate denies the agent a command that carries it, as it denies `close.sh --human`.
#
# ONE PLAN, A FRONT IN EVERY REPOSITORY IT CITES (0.8.0). The fences judge a file by the repository
# it is in, so a Scope line about another repository -- written from home, as an absolute path, or
# as a path into a repository nested in the plan's that keeps a rite of its own -- needs a front
# THERE. hooks/planblocks.py (`by_repository`) divides the Scope and the Verification by the rule
# the fences use, and this script opens every front in one act: in each repository, its part of the
# scope (relative to it), the gates that are its own (a command that starts with `cd <it> && ...`)
# and a snapshot. Every snapshot carries the WHOLE lists (`plan_scope`, `plan_gates`: what the
# fingerprint of the approval is computed from), the local ones (`scope_globs`, `gates`: what the
# lock enforces there), the plan's repository (`plan_root`: where the gates run from, so the `cd`
# written in the plan means what it says, and where the front closes from) and the repositories of
# the front (`front_roots`). All or nothing: a cited repository left with no gate, or holding a live
# front of another plan, refuses the whole opening before anything is written.
#
# WHERE THE FRONT OPENS FROM. `--root`, when given. Else the repository the script runs in --
# unless the plan declares (`project:`) a repository that HOLDS that one, the session having
# entered a subproject that is a repository of its own: then the plan's. The plan gate judges such
# a plan in its own repository from 0.8.0 (hooks/plan-review-gate), and the front follows it.
#
# THE STANDING GATES (0.8.0). What a project asks of EVERY closing is the owner's to say, in
# `.roadworthy/standing-gates`: one command per line, `#` comments. They are joined to the gates of
# the front here, after the plan's (one the plan already declares is not repeated), so the closing
# runs them like any gate. The snapshot keeps them APART (`standing_gates`): its `gates` stay the
# plan's, because the fingerprint an approval approved is computed from those, and a project that
# adds a standing gate must not void every approval on record. Until 0.8.0 the quality bar of a
# project was the Verification block of its newest plan, copied by hand into the next one.
#
# Usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>] [--owner]
set -euo pipefail
usage="usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>] [--owner]"
plan=""; root=""; base=""; owner=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="${2:?--root needs a directory}"; shift 2 ;;
    --base) base="${2:?--base needs a ref}"; shift 2 ;;
    --owner) owner="owner"; shift ;;
    -*) echo "scope-write: unknown argument $1" >&2; exit 1 ;;
    *) [ -z "$plan" ] || { echo "scope-write: unknown argument $1" >&2; exit 1; }
       plan="$1"; shift ;;
  esac
done
[ -n "$plan" ] || { echo "$usage" >&2; exit 1; }
[ -f "$plan" ] || { echo "scope-write: plan not found: $plan" >&2; exit 1; }
plan="$(cd "$(dirname "$plan")" && pwd -P)/$(basename "$plan")"
# Resolved BEFORE the cd below: the script may have been named by a relative path.
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -z "$root" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "scope-write: not a git repository; give --root" >&2; exit 1; }
  # The session entered a subproject that is a repository of its own, and the plan is the plan of
  # the repository that holds it: the front opens from the plan's.
  declared="$(python3 "$here/../../../hooks/planblocks.py" project-root "$plan" 2>/dev/null || true)"
  if [ -n "$declared" ]; then
    case "$(cd "$root" && pwd -P)" in "$declared"/*) root="$declared" ;; esac
  fi
fi
cd "$root"

python3 - "$plan" "$base" "$here/../../../hooks" "$owner" <<'PY'
import hashlib, json, os, subprocess, sys, time

plan = sys.argv[1]
base_arg = sys.argv[2] if len(sys.argv) > 2 else ""
opened_by = sys.argv[4] if len(sys.argv) > 4 else ""
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[3])
from globmatch import matches
from planblocks import blocks, by_repository, fingerprint, header, project_root

def refuse(msg):
    sys.stderr.write("scope-write: " + msg + "\n")
    sys.exit(1)

text = open(plan, encoding="utf-8").read()
globs, gates, declared_base = blocks(text)
missing = []
if globs is None: missing.append("a '## Scope' ('## Escopo') section with a fenced block")
if gates is None: missing.append("a '## Verification' ('## Verificação') section with a fenced block")
if missing:
    refuse("the plan is missing " + "; and ".join(missing) +
           ".\nBoth are read as fenced blocks, never as prose: close.sh runs each gate line "
           "with `bash -c`, and a bullet like `- `cmd` -> expected` is not a command.")
if not globs: refuse("the Scope block is empty; a front with no scope is not a front.")
if not gates: refuse("the Verification block declares no gate; close.sh cannot close without one.")

name = os.path.basename(plan)
plan_root = os.path.realpath(os.getcwd())
order, parts = by_repository(plan_root, globs, gates)

def git(root, *args):
    return subprocess.run(["git", "-C", root] + list(args), capture_output=True)

def rev(root, ref):
    r = git(root, "rev-parse", "--verify", "--quiet", ref + "^{commit}")
    return r.stdout.decode().strip() if r.returncode == 0 else ""

def sha(path):
    try:
        return hashlib.sha256(open(path, "rb").read()).hexdigest()
    except Exception:
        return ""

# ── first, everything that can refuse: nothing is written in any repository before this ends ──
fronts = []
for root in order:
    rw = os.path.join(root, ".roadworthy")
    here = "here" if root == plan_root else "in " + root
    local_globs, local_gates = parts[root]["scope"], parts[root]["gates"]
    if not local_globs:
        refuse("every line of the Scope belongs to another repository than the one this front opens from (%s). "
               "Open it from the repository the plan is about: --root <repository>." % root)
    # The standing gates of the project: the owner's file, read as it is now -- a front reopened
    # runs what the owner asks today.
    standing = []
    try:
        with open(os.path.join(rw, "standing-gates"), encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.rstrip()
                if line.strip() and not line.strip().startswith("#") and line not in local_gates and line not in standing:
                    standing.append(line)
    except FileNotFoundError:
        pass
    if not local_gates and not standing:
        refuse("the Scope cites the repository %s and no gate of the Verification is that repository's: a front "
               "with no gate cannot close. A gate belongs to a repository other than the plan's when its command "
               "starts with `cd <that repository> && ...`. Add one, or take those lines out of the Scope. Nothing "
               "was written." % root)
    # The front that is live there, if any: a scope the rite wrote, and the snapshot written with it.
    live = None
    try:
        with open(os.path.join(rw, "scope"), encoding="utf-8", errors="replace") as fh:
            rite_wrote = "Written by scope-write.sh" in fh.readline()
    except Exception:
        rite_wrote = False
    if rite_wrote:
        try:
            live = json.load(open(os.path.join(rw, "plan.snapshot"), encoding="utf-8"))
        except Exception:
            live = {}
    if live is not None and live.get("plan_name") and live["plan_name"] != name:
        refuse("a second front opened over a live one is refused. A front is already open %s, from %s (since %s). "
               "One front at a time: close it (skills/close/scripts/close.sh) or abandon it with its reason "
               "(close.sh --abandon \"<reason>\"), then open this one.%s"
               % (here, live["plan_name"], live.get("ts", "an unknown time"),
                  "" if len(order) == 1 else " Nothing was written in any repository."))
    if live and live.get("base_head"):
        # The same front, reopened: its base is the one it opened with.
        head = live["base_head"]
        if root == plan_root and base_arg and rev(root, base_arg) != head:
            refuse("this front opened at %s and --base %s is another commit. Reopening keeps the base: it is what "
                   "the closing measures the front's diff against. Drop --base, or abandon the front "
                   "(close.sh --abandon \"<reason>\") and open a new one." % (head[:12], base_arg))
        reopened = True
    else:
        # A NEW front: in the plan's repository the base is the one named, else the tip; in every
        # other repository of the front, its own tip.
        wanted = base_arg if (base_arg and root == plan_root) else "HEAD"
        head = rev(root, wanted)
        if not head:
            refuse("base %s does not resolve to a commit %s." % (wanted, here))
        reopened = False
    fronts.append({"root": root, "rw": rw, "globs": local_globs, "gates": local_gates, "standing": standing,
                   "live": live, "head": head, "reopened": reopened})

# ── then every front, written ──────────────────────────────────────────────────────────────────
banner = (f"# Written by scope-write.sh from {name}. Do not edit by hand: the closing is measured\n"
          f"# against .roadworthy/plan.snapshot, and a hand edit here only makes the digests disagree.\n")
# The rite's local state is not content. A project that does not ignore it commits the scope and
# the snapshot with the first `git add -A`, and from then on a `git stash` or a `git checkout .`
# brings an OLD scope back in silence (found by the simulation of honest work, 2026-10-01). So
# what is not ignored yet is ignored here, in the repository's own exclude file -- local to this
# clone, never a change to the project. What is already TRACKED cannot be fixed that way; it is said.
LOCAL = ["scope", "state", "plan.snapshot", "overnight", "evidence.jsonl", "denials.jsonl",
         "refutations.jsonl", "preflight.jsonl", "readings.jsonl", "stop-latch/"]
now = time.strftime("%Y-%m-%dT%H:%M:%S")
for f in fronts:
    root, rw, live = f["root"], f["rw"], f["live"]
    os.makedirs(rw, exist_ok=True)
    with open(os.path.join(rw, "scope"), "w", encoding="utf-8") as fh:
        fh.write(banner + "\n".join(f["globs"]) + "\n")
    with open(os.path.join(rw, "gates"), "w", encoding="utf-8") as fh:
        fh.write(banner + "\n".join(f["gates"] + f["standing"]) + "\n")
    # What is already changed outside the scope, with its content: it was there before this front,
    # and the fence that measures the tree against the scope (hooks/frontcheck.py) and the closing
    # leave it alone until it changes again. A reopened front keeps the list it opened with.
    if f["reopened"] and isinstance(live.get("preexisting"), dict):
        preexisting = live["preexisting"]
    else:
        preexisting = {}
        st = git(root, "status", "--porcelain", "-z", "-uall")
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
                if not p.startswith(".roadworthy/") and not matches(p, f["globs"]):
                    preexisting[p] = sha(os.path.join(root, p))
    snap = {"ts": live["ts"] if f["reopened"] and live.get("ts") else now,
            "plan": os.path.abspath(plan), "plan_name": name,
            "base_head": f["head"], "scope_globs": f["globs"], "gates": f["gates"],
            "plan_scope": globs, "plan_gates": gates, "plan_root": plan_root, "front_roots": order,
            "plan_project": project_root(text),
            "declared_base": declared_base, "fingerprint": fingerprint(text),
            "report": header(text, "report|relato"), "preexisting": preexisting}
    if f["standing"]:
        snap["standing_gates"] = f["standing"]
    if opened_by:
        snap["opened_by"] = opened_by
    canonical = json.dumps(snap, sort_keys=True, separators=(",", ":"))
    snap["digests"] = {"scope": sha(os.path.join(rw, "scope")),
                       "gates": sha(os.path.join(rw, "gates")),
                       "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
    with open(os.path.join(rw, "plan.snapshot"), "w", encoding="utf-8") as fh:
        json.dump(snap, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    f["preexisting"] = preexisting
    names = [".roadworthy/" + n.rstrip("/") for n in LOCAL]
    f["tracked"] = [l for l in git(root, "ls-files", "--", *names).stdout.decode().splitlines() if l]
    loose = [n for n in LOCAL if ".roadworthy/" + n.rstrip("/") not in f["tracked"] and
             git(root, "check-ignore", "-q", ".roadworthy/" + n.rstrip("/")).returncode != 0]
    if loose:
        try:
            ex = git(root, "rev-parse", "--git-path", "info/exclude").stdout.decode().strip()
            ex = ex if os.path.isabs(ex) else os.path.join(root, ex)
            os.makedirs(os.path.dirname(ex), exist_ok=True)
            with open(ex, "a", encoding="utf-8") as fh:
                fh.write("# Roadworthy: the rite's local state (written by scope-write.sh)\n" +
                         "".join(".roadworthy/%s\n" % n for n in loose))
        except Exception:
            pass

first = fronts[0]
print(f"scope-write: front {'reopened' if first['reopened'] else 'open'} from {name}" +
      (f", in {len(fronts)} repositories" if len(fronts) > 1 else ""))
for f in fronts:
    if len(fronts) > 1:
        print(f"  repository {f['root']}" + ("  (the plan's: the front closes from here)" if f["root"] == plan_root else ""))
    print(f"  base HEAD  {f['head'][:12] or '(no commits)'}{'  (kept from when the front opened)' if f['reopened'] else ''}")
    print(f"  scope      {len(f['globs'])} glob(s) -> .roadworthy/scope")
    print(f"  gates      {len(f['gates'])} command(s) -> .roadworthy/gates" +
          (f", and {len(f['standing'])} standing gate(s) of the project (.roadworthy/standing-gates)" if f["standing"] else ""))
    print(f"  snapshot   .roadworthy/plan.snapshot")
    if f["preexisting"]:
        print(f"  note       {len(f['preexisting'])} path(s) outside the scope were already changed when the front opened; they are not this front's")
    if f["tracked"]:
        print(f"  warning    the rite's local state is TRACKED by git here ({', '.join(f['tracked'])}): a stash or a checkout will bring an old scope back. Untrack it: git rm --cached {' '.join(f['tracked'])}")
if opened_by:
    print(f"  opened by the owner, outside the agent: it stands with no approval on record")
report = header(text, "report|relato")
if report:
    print(f"  report     {report}")
PY
