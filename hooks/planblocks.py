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
Import: sys.path.insert(0, "<plugin>/hooks"); from planblocks import blocks, fingerprint
"""
import hashlib
import json
import os
import re
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
    your plan"; 112 rejected ones carry an error result."""
    calls, results = {}, {}
    for rec in _records(transcript):
        content = (rec.get("message") or {}).get("content")
        if not isinstance(content, list):
            continue
        for block in content:
            if not isinstance(block, dict):
                continue
            if block.get("type") == "tool_use" and block.get("name") == "ExitPlanMode":
                calls[block.get("id")] = (block.get("input") or {}).get("plan") or ""
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
