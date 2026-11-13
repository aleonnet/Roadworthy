#!/usr/bin/env python3
"""planblocks — what a plan declares to the machine, read by one grammar.

A plan says three things a script acts on: its SCOPE (the globs the lock enforces), its
VERIFICATION (the commands the closing runs) and its BASE (the commit the front is measured
from). Until 0.7.0 that grammar lived inside skills/plan/scripts/scope-write.sh, and nothing else
could ask "is this the plan that was approved?" -- so the script that opens a front read ANY plan
and accepted any `--base` (field note, 2026-09-18).

The FINGERPRINT is what an approval approves: the SHA-256 of the scope globs, the gate commands
and the declared base, in a canonical form. Editing the prose of a plan after it was approved does
not change it (the owner's decision of 0.3.0, kept: a review is bound to the plan by name, and an
approval to what the plan makes the machine do). Changing a glob, a gate or the base does.

Both sections are read as FENCED BLOCKS, never as prose bullets: close.sh runs each gate line with
`bash -c`, and `- \\`cmd\\` -> expected` is not a command.

Usage:
  planblocks.py fingerprint <plan.md>          the fingerprint, or exit 1 with the reason
  planblocks.py header <plan.md> <key|key>     a header line of the plan (before the first `## `)
  planblocks.py approved <plan.md> <evidence.jsonl> [<transcript.jsonl>]
                                               exit 0 when an approval with this plan's
                                               fingerprint is on record; 1 otherwise
  planblocks.py root <path>                    the repository a path belongs to, or nothing
  planblocks.py project-root <plan.md>         the repository the plan declares in `project:`,
                                               when that line names the top level of one
  planblocks.py reaches <plan.md> <from> <to>  exit 0 when an approval of the plan recorded for
                                               the repository <from> covers a front in <to>
Import: sys.path.insert(0, "<plugin>/hooks"); from planblocks import blocks, fingerprint

A PLAN MAY CITE SEVERAL REPOSITORIES (0.8.0). Its Scope is one list, and a line of it may name a
file of another repository: written from home or as an absolute path, or as a path into a
repository nested in the plan's that keeps a rite of its own (a monorepo whose subprojects are
repositories). The fences judge a file by the repository IT is in (`rw_target_root`, hooks/lib.sh),
so a front that lives only in the plan's repository left those lines enforced by nobody and the
files they name denied for want of a front: 27 refusals measured in the field between 2026-10-02
and 2026-11-13. `by_repository` splits the Scope and the Verification by the repository each line
belongs to, with the same rule the fences use (`repo_of`), and the script that opens a front opens
one in each.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import time

SCOPE_TITLES = ("scope", "escopo")
GATE_TITLES = ("verification", "verificação", "verificacao")


def fenced(text, titles):
    """The first fenced block of the first `## ` section whose heading starts with one of
    `titles`: its non-blank, non-comment lines; None when there is no such block."""
    lines = text.splitlines()
    for line_no, line in enumerate(lines):
        if not line.startswith("## "):
            continue
        head = line[3:].strip().lower()
        if not any(head.startswith(t) for t in titles):
            continue
        block, inside = [], False
        for l in lines[line_no + 1:]:
            if l.startswith("## "):
                break
            if l.strip().startswith("```"):
                if inside:
                    return [b for b in block if b.strip() and not b.strip().startswith("#")]
                inside = True
                continue
            if inside:
                block.append(l.rstrip())
    return None


def header(text, keys):
    """A `key: value` line of the plan's header -- what comes before the first `## ` heading, so
    the fields of an in-plan review section are never taken for the plan's."""
    pre = text.split("\n## ", 1)[0]
    m = re.search(r"^(?:%s):[ \t]*(.*)$" % keys, pre, re.M)
    return m.group(1).strip() if m else ""


def blocks(text):
    """(scope globs, gate commands, declared base). A missing block is None."""
    return fenced(text, SCOPE_TITLES), fenced(text, GATE_TITLES), header(text, "base")


def fingerprint(text):
    """The fingerprint of what the plan makes the machine do, or "" when it declares no scope or
    no gate: such a plan opens no front, so there is nothing to approve."""
    globs, gates, base = blocks(text)
    if not globs or not gates:
        return ""
    canonical = json.dumps({"scope": globs, "gates": gates, "base": base},
                           sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


_TOPS = {}


def _git_top(d):
    """The top level of the repository a directory is in, or "". Asked once per directory."""
    if d not in _TOPS:
        try:
            r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
            _TOPS[d] = r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            _TOPS[d] = ""
    return _TOPS[d]


def repo_of(path, has_rite=()):
    """The repository a FILE belongs to, by the rule of `rw_target_root` (hooks/lib.sh), which is
    the one the fences judge a target by: the top level of the repository that holds its deepest
    existing ancestor; a repository nested in another one that has no `.roadworthy` of its own
    answers to the nearest repository above it that has one, and is its own when none above has.
    "" when the path is in no repository. `has_rite` names repositories counted as having the
    directory already: the one a front is about to open in. tests/scripts/front-roots.sh hands
    one table of paths to both resolvers."""
    d = path
    while d not in ("/", ".", "") and not os.path.isdir(d):
        d = os.path.dirname(d)
    top = _git_top(d) if d else ""
    if not top:
        return ""

    def rite(t):
        return os.path.isdir(os.path.join(t, ".roadworthy")) or os.path.realpath(t) in has_rite
    at, n = top, 0
    while not rite(top) and n < 8:
        up = _git_top(os.path.dirname(at))
        if not up or up == at:
            break
        if rite(up):
            top = up
            break
        at, n = up, n + 1
    return os.path.realpath(top)


def project_root(text):
    """The repository a plan declares in its `project:` line, resolved -- only when the line names
    the top level of a repository. "" otherwise."""
    declared = header(text, "project|projeto")
    if not declared:
        return ""
    p = os.path.realpath(os.path.expanduser(declared))
    top = _git_top(p) if os.path.isdir(p) else ""
    return p if top and os.path.realpath(top) == p else ""


def _literal(pattern):
    """The part of a path pattern that is a plain path: all of it when it has no wildcard, else
    what comes before the component that carries the first one."""
    cuts = [pattern.index(c) for c in "*?[" if c in pattern]
    if not cuts:
        return pattern
    head = pattern[:min(cuts)]
    return head[:head.rfind("/") + 1]


def by_repository(plan_root, globs, gates):
    """(order, parts): the repositories a plan's Scope cites, the plan's own first, and for each
    one its part of the Scope -- relative to it -- and of the Verification.

    A relative line is resolved against the plan's repository; an absolute one, or one written
    from home, as it is. The repository of a line is the one of its literal part (`repo_of`). A
    line in no repository stays with the plan's, written in full, which is how the scope lock
    compares a target outside every repository. A gate whose command starts with `cd <directory>`
    goes to the repository of that directory, when the Scope cites it; every other gate is the
    plan's."""
    plan_root = os.path.realpath(plan_root)
    has = (plan_root,)
    order, parts = [plan_root], {plan_root: {"scope": [], "gates": []}}
    for g in globs:
        written_whole = g.startswith(("/", "~"))
        full = os.path.expanduser(g) if written_whole else os.path.join(plan_root, g)
        lit = _literal(full)
        owner = repo_of(lit, has) if lit else ""
        if not owner:
            parts[plan_root]["scope"].append(full if written_whole else g)
            continue
        if owner == plan_root and not written_whole:
            parts[plan_root]["scope"].append(g)
            continue
        # The line as the repository it belongs to sees it: its literal part resolved (so that
        # /var and /private/var are one directory), then made relative to that repository.
        if lit == full:
            rel = os.path.relpath(os.path.realpath(full), owner)
        else:
            base = os.path.relpath(os.path.realpath(lit), owner)
            rel = full[len(lit):] if base == "." else base + "/" + full[len(lit):]
        if rel == ".." or rel.startswith("../"):
            parts[plan_root]["scope"].append(full if written_whole else g)
            continue
        if owner not in parts:
            order.append(owner)
            parts[owner] = {"scope": [], "gates": []}
        parts[owner]["scope"].append(rel)
    for cmd in gates:
        owner = plan_root
        m = re.match(r"""\s*cd\s+("[^"]+"|'[^']+'|[^\s;&|]+)\s*(?:&&|;)""", cmd)
        if m:
            d = os.path.expanduser(m.group(1).strip("\"'"))
            d = d if os.path.isabs(d) else os.path.join(plan_root, d)
            found = repo_of(os.path.join(d, "x"), has)
            if found in parts:
                owner = found
        parts[owner]["gates"].append(cmd)
    return order, parts


def reaches(source_root, target_root, globs, gates):
    """Whether an approval of a plan recorded for `source_root` covers a front of it in
    `target_root`: the same repository, or one the plan's Scope cites when it is read from the
    source. The fingerprint covers the scope, the gates and the base and nothing else, so without
    this an approval recorded in one repository opened a front in ANY other for a plan with the
    same two blocks and a `project:` line pointing at the first (cold review, 2026-11-13)."""
    if not source_root or not target_root:
        return False
    source, target = os.path.realpath(source_root), os.path.realpath(target_root)
    if source == target:
        return True
    order, _ = by_repository(source, globs or [], gates or [])
    return target in order


def _records(path):
    if not path or not os.path.exists(path):
        return
    with open(path, encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            if isinstance(rec, dict):
                yield rec


def approved_in_ledger(fp, ledger):
    """An approval this plugin recorded when the plan-mode exit was approved."""
    return any(r.get("kind") == "approval" and r.get("fingerprint") == fp for r in _records(ledger))


def approved_in_transcript(fp, transcript):
    """The same fact, read from the transcript the harness writes: a plan-mode exit whose plan
    text has this fingerprint and whose result is not an error. Measured on this machine on
    2026-09-30: 126 approved exits carry a non-error result starting with "User has approved
    your plan"; 112 rejected ones carry an error result.

    One call is recorded more than once under the same id: as the assistant's message, with the
    plan in its input, and again as the request sent on (`api-request-blob`), with the input
    empty. Measured on 2026-11-13, in the transcripts of two projects changed in the last 45 days:
    20 of 26 approved exits. The plan of a call is the first one
    that is not empty; keeping the last record made the empty one the plan, and the approval was
    not found."""
    calls, results = {}, {}
    for rec in _records(transcript):
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use" and block.get("name") == "ExitPlanMode":
                plan_text = (block.get("input") or {}).get("plan") or ""
                if plan_text and not calls.get(block.get("id")):
                    calls[block.get("id")] = plan_text
            elif block.get("type") == "tool_result":
                body = block.get("content")
                if isinstance(body, list):
                    body = " ".join(b.get("text", "") for b in body if isinstance(b, dict))
                results[block.get("tool_use_id")] = (bool(block.get("is_error")), str(body or ""))
    for call_id, plan_text in calls.items():
        if call_id not in results or fingerprint(plan_text) != fp:
            continue
        is_error, body = results[call_id]
        if not is_error and "approved your plan" in body:
            return True
    return False


def main(argv):
    if len(argv) >= 3 and argv[1] == "fingerprint":
        try:
            fp = fingerprint(open(argv[2], encoding="utf-8").read())
        except Exception as e:
            sys.stderr.write("planblocks: cannot read %s: %s\n" % (argv[2], e))
            return 1
        if not fp:
            sys.stderr.write("planblocks: %s declares no Scope or no Verification as a fenced block\n" % argv[2])
            return 1
        print(fp)
        return 0
    if len(argv) >= 3 and argv[1] == "root":
        found = repo_of(argv[2])
        if found:
            print(found)
        return 0
    if len(argv) >= 5 and argv[1] == "reaches":
        try:
            globs, gates, _ = blocks(open(argv[2], encoding="utf-8").read())
        except Exception:
            return 1
        return 0 if reaches(argv[3], argv[4], globs, gates) else 1
    if len(argv) >= 3 and argv[1] == "project-root":
        try:
            found = project_root(open(argv[2], encoding="utf-8").read())
        except Exception:
            found = ""
        if found:
            print(found)
        return 0
    if len(argv) >= 4 and argv[1] == "header":
        try:
            print(header(open(argv[2], encoding="utf-8").read(), argv[3]))
        except Exception:
            print("")
        return 0
    if len(argv) >= 4 and argv[1] == "approved":
        try:
            fp = fingerprint(open(argv[2], encoding="utf-8").read())
        except Exception:
            return 1
        if not fp:
            return 1
        if approved_in_ledger(fp, argv[3]):
            return 0
        if len(argv) > 4 and approved_in_transcript(fp, argv[4]):
            # Written down where the fences look, so the approval is found again without
            # reading the whole transcript on every tool call.
            try:
                os.makedirs(os.path.dirname(argv[3]), exist_ok=True)
                with open(argv[3], "a", encoding="utf-8") as fh:
                    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "kind": "approval",
                                         "cmd": "approval: " + os.path.basename(argv[2]),
                                         "plan_name": os.path.basename(argv[2]), "fingerprint": fp,
                                         "source": "transcript", "exit": 0}) + "\n")
            except Exception:
                pass
            return 0
        return 1
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
