#!/usr/bin/env python3
"""frontcheck — the open front, measured by what is on disk instead of by what a command said.

The entry gate reads commands, and a reader of commands has a ceiling: a program that opens the
file itself (an interpreter, a script, a build tool) writes through nothing a reader can name.
25.7% of 33,811 real commands use one (measured 2026-09-30), so denying what cannot be read is not
an option. What IS exact is the result. Two questions, both answered from the repository:

  INTACT?  A front the rite opened is its scope, its gates and the snapshot of what was approved.
           The snapshot carries the SHA-256 of the first two and of its own canonical form; and,
           from 0.7.0, the fingerprint of the plan, which has to match an approval on record. A
           scope edited by any means -- an editor, `python3 -c`, a script -- no longer matches,
           and a scope that does not match what was approved is not a scope.

  DRIFT?   Every path git reports as changed or new that the scope does not cover, the owner did
           not free, and that was not already like that when the front opened. However it got
           there. While there is one, the gate lets nothing else be written: undoing it is the
           only act that passes.

Output, one fact per line:
  BROKEN <TAB> reason        the front on disk is not the front that was approved
  DRIFT  <TAB> path          a change outside the scope, in the tree
  HISTORY <TAB> path         a change outside the scope, already committed since the front's base
Nothing printed means an intact front with no drift, or no front the rite opened (a scope written
by hand, as toy repositories and projects from before 0.6.0 have, carries no snapshot to measure
against and is left to the closing).

Usage: frontcheck.py <root> <ledger> <review required: true|false> [<plans dir>...]
"""
import hashlib
import json
import os
import subprocess
import sys

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from globmatch import matches  # noqa: E402

BANNER = "Written by scope-write.sh"


def sha(path):
    try:
        with open(path, "rb") as fh:
            return hashlib.sha256(fh.read()).hexdigest()
    except Exception:
        return ""


def listed(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return [l.strip() for l in fh if l.strip() and not l.strip().startswith("#")]
    except Exception:
        return []


def approved(fp, ledger):
    try:
        with open(ledger, encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                if '"approval"' not in raw:
                    continue
                try:
                    r = json.loads(raw)
                except Exception:
                    continue
                if r.get("kind") == "approval" and r.get("fingerprint") == fp:
                    return True
    except Exception:
        pass
    return False


def broken(root, ledger, review_required):
    rw = os.path.join(root, ".roadworthy")
    scope, gates, snap_path = (os.path.join(rw, n) for n in ("scope", "gates", "plan.snapshot"))
    try:
        with open(scope, encoding="utf-8", errors="replace") as fh:
            first = fh.readline()
    except Exception:
        return None, None
    if BANNER not in first:
        return None, None                       # a scope written by hand: nothing to measure against
    if not os.path.exists(snap_path):
        return "the scope was written by the rite and .roadworthy/plan.snapshot is gone", None
    try:
        snap = json.load(open(snap_path, encoding="utf-8"))
    except Exception:
        return ".roadworthy/plan.snapshot cannot be read", None
    declared = snap.get("digests") or {}
    bare = {k: v for k, v in snap.items() if k != "digests"}
    canonical = json.dumps(bare, sort_keys=True, separators=(",", ":"))
    now = {"scope": sha(scope), "gates": sha(gates),
           "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
    for key, what in (("scope", ".roadworthy/scope"), ("gates", ".roadworthy/gates"),
                      ("snapshot_canonical", ".roadworthy/plan.snapshot")):
        if declared.get(key) != now[key]:
            return "%s is not what the approval snapshot recorded" % what, snap
    fp = snap.get("fingerprint")
    if fp:
        again = json.dumps({"scope": snap.get("scope_globs") or [], "gates": snap.get("gates") or [],
                            "base": snap.get("declared_base") or ""},
                           sort_keys=True, separators=(",", ":"), ensure_ascii=False)
        if hashlib.sha256(again.encode("utf-8")).hexdigest() != fp:
            return "the snapshot's fingerprint is not the fingerprint of its own scope, gates and base", snap
        if review_required and not approved(fp, ledger):
            return "no approval is on record for the scope, the gates and the base this front enforces", snap
    return None, snap


history = []


def front_paths(root, base):
    """The paths THIS front changed in the history since its base: in the difference between the
    base and HEAD, and touched by a commit made here. A commit that arrived from somewhere else --
    a pull, a merge of the upstream, a rebase onto it -- is somebody else's work. Git's own reflog
    says which is which: a commit made in this clone is recorded there as `commit`, `cherry-pick`,
    `revert` or a `rebase` step; what a `pull` or a `merge` brought is everything reachable from
    the tip it moved to (a fast-forward) or from the second parent of the merge it made.
    Counting those charged the front for a colleague's file and told the agent to take the
    colleague's commit out of the history (adversarial simulation, 2026-10-01). Names are read
    NUL-separated: git quotes a name with a non-ASCII character otherwise, and a quoted name
    matches no glob."""
    def git(*args):
        r = subprocess.run(["git", "-C", root] + list(args), capture_output=True)
        return r.stdout.decode("utf-8", errors="replace") if r.returncode == 0 else ""
    if not base:
        return set()
    endpoint = {p for p in git("diff", "--name-only", "-z", base + "..HEAD").split("\0") if p}
    if not endpoint:
        return set()
    commits = [c for c in git("rev-list", "--no-merges", base + "..HEAD").split() if c]
    made_here, arrived = set(), set()
    for line in git("reflog", "--format=%H%x09%gs").splitlines():
        sha, _, subject = line.partition("\t")
        if subject.startswith(("commit", "cherry-pick", "revert", "rebase")):
            made_here.add(sha)
        elif subject.startswith(("pull", "merge")):
            arrived |= set(git("rev-list", "--no-merges", base + ".." + sha).split())
    for merge in git("rev-list", "--merges", base + "..HEAD").split():
        arrived |= set(git("rev-list", "--no-merges", merge + "^1.." + merge + "^2").split())
    touched = set()
    for c in commits:
        if c in arrived and c not in made_here:
            continue                            # brought by a pull or a merge: not this front's
        touched |= {p for p in git("diff-tree", "--no-commit-id", "--name-only", "-r", "-z", "--root", c).split("\0") if p}
    return endpoint & touched


def in_progress(root):
    """Whether git is in the middle of a merge, a rebase, a cherry-pick or a revert: the index
    then holds the OTHER side's changes, which are not a drift of this front."""
    r = subprocess.run(["git", "-C", root, "rev-parse", "--git-dir"], capture_output=True, text=True)
    if r.returncode != 0:
        return False
    gd = r.stdout.strip()
    gd = gd if os.path.isabs(gd) else os.path.join(root, gd)
    return any(os.path.exists(os.path.join(gd, n)) for n in
               ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge", "rebase-apply"))


def drift(root, snap, plan_dirs):
    globs = (snap or {}).get("scope_globs") or listed(os.path.join(root, ".roadworthy", "scope"))
    free = listed(os.path.join(root, ".roadworthy", "free"))
    before = (snap or {}).get("preexisting") or {}
    r = subprocess.run(["git", "-C", root, "status", "--porcelain", "-z", "-uall"], capture_output=True)
    if r.returncode != 0:
        return []
    out, entries = [], r.stdout.decode("utf-8", errors="replace").split("\0")
    # What the front already COMMITTED outside its scope: the same question the closing asks
    # (base..HEAD), asked at every write instead of only at the end. A commit made by a route no
    # reader of commands recognises is found here, by what it left in the history.
    for p in front_paths(root, (snap or {}).get("base_head") or ""):
        if p == ".roadworthy" or p.startswith(".roadworthy/"):
            continue
        if matches(p, globs) or (free and matches(p, free)):
            continue
        full = os.path.join(root, p)
        if p.endswith(".md") and os.path.dirname(os.path.realpath(full)) in plan_dirs:
            continue
        history.append(p)
    # Mid-merge, mid-rebase: what sits in the index came from the other side, and the conflict in
    # a file of the scope has to be resolvable. The tree is measured again when git is done.
    if in_progress(root):
        return []
    i = 0
    while i < len(entries):
        e = entries[i]
        i += 1
        if len(e) < 4:
            continue
        status, path = e[:2], e[3:]
        paths = [path]
        if status[0] in "RC" and i < len(entries):      # a rename carries the old path next
            paths.append(entries[i])
            i += 1
        for p in paths:
            if p == ".roadworthy" or p.startswith(".roadworthy/"):
                continue                                # the rite's own files answer to the rite
            if matches(p, globs) or (free and matches(p, free)):
                continue
            full = os.path.join(root, p)
            if p.endswith(".md") and os.path.dirname(os.path.realpath(full)) in plan_dirs:
                continue                                # the plan is the rite's own artefact
            if p in before and before[p] == sha(full):
                continue                                # it was like that when the front opened
            out.append(p)
    return sorted(set(out))


def main(argv):
    if len(argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    root, ledger, review_required = argv[1], argv[2], argv[3] == "true"
    plan_dirs = {os.path.realpath(d) for d in argv[4:] if d}
    reason, snap = broken(root, ledger, review_required)
    if reason:
        print("BROKEN\t" + reason)
        return 0
    if snap is None:
        return 0
    for p in drift(root, snap, plan_dirs):
        print("DRIFT\t" + p)
    for p in sorted(set(history)):
        print("HISTORY\t" + p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
