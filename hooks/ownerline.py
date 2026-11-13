#!/usr/bin/env python3
"""ownerline — the orders an owner gives in the chat, read from the prompt by one grammar.

Some acts of the rite are a PERSON's: answering a human verification, approving the closing of a
front. Until 0.7.0 the only way to record one was a command, which an agent can type as easily as
the owner. The prompt is the one text of a session the agent did not write, so the owner's hook
(hooks/principles, UserPromptSubmit) reads these orders from it:

    rw-human: all approved                    a line of its own; `aprovado`, `rejected <note>` too
    rw-human: <item or id> rejected <note>
    aprovado | aprovada | approved            the WHOLE message, and nothing else
    reprovado <motivo> | rejected <reason>    the whole message, starting with the word
    rw-principios: aceito                     the owner agrees to the principles file as it is now
    rw-config: [<repository>] <file> + <line> adds a line to one of the owner's files; `- <line>`
                                              removes it. <file> is protected, free, rites,
                                              overnight-rules or standing-gates.
    rw-config: [<repository>] docs.json <key> = <value>

THE OWNER'S FILES (0.8.0). Six files under .roadworthy/ are what the fences read to guard against
the agent, so the agent never writes them (hooks/rite-gate), and until 0.8.0 the owner could only
change them outside the agent, by hand: 6 of the 113 refusals measured in the field between
2026-10-02 and 2026-11-13 were an agent in front of one of them with nobody to turn to. A
`rw-config:` line is the owner changing one, in the owner's own words. With no repository named it
is the one the session stands in. A file that is not one of the six, a line to remove that is not
there, a docs.json that is not valid JSON as it stands: nothing is written, and the reason is said.
In `rites` a key is SET -- the fences read the first line of a key, so a second line would say
nothing: `+ plan_gate: both` replaces the line that was there.

A marker only counts at the START OF A LINE, and the bare word only as the whole message: in the
middle of a sentence both are conversation ("acho que está aprovado, mas...").

The limit, declared: the channel trusts the prompt the person submitted. A text the person pasted
that carries one of these lines at the start of a line is the person's order.

Output, one order per line, fields separated by tabs (a tab or a newline inside a field becomes a
space):
    human <TAB> item <TAB> approved|rejected <TAB> note
    word  <TAB> approved|rejected <TAB> note
    principles <TAB> accept
    config <TAB> what follows the marker, to be handed back to --apply-config
    error <TAB> what was wrong with a line that carried a marker

Usage: ownerline.py            the prompt in the environment variable RW_PROMPT
       ownerline.py --apply-config <the session's repository> <the session's directory> <spec>
                               applies one `rw-config:` line; prints what was done and exits 0, or
                               prints why nothing was written and exits 1
"""
import json
import os
import re
import subprocess
import sys

OWNER_FILES = ("protected", "free", "rites", "overnight-rules", "standing-gates", "docs.json")
ACCEPT = ("aceito", "aceita", "aceitos", "accepted", "accept")

VERDICTS = {"approved": "approved", "aprovado": "approved", "aprovada": "approved",
            "rejected": "rejected", "reprovado": "rejected", "reprovada": "rejected"}
WORD = re.compile(r"(?<!\S)(%s)(?!\S)" % "|".join(VERDICTS), re.I)
ALL = ("", "all", "tudo", "todas", "todos")


def flat(text):
    return " ".join(text.replace("\t", " ").split())


def orders(prompt):
    out = []
    for line in prompt.splitlines():
        m = re.match(r"\s*rw-princ[ií]p(?:ios|les):\s*(.*)$", line, re.I)
        if m:
            if flat(m.group(1)).rstrip(".!").lower() in ACCEPT:
                out.append(("principles", "accept"))
            else:
                out.append(("error", "A 'rw-principios:' line says one thing, 'aceito' (the owner agrees to the "
                                     "principles file as it is now); this one does not: " + flat(line)))
            continue
        m = re.match(r"\s*rw-config:\s*(.*)$", line, re.I)
        if m:
            out.append(("config", flat(m.group(1))))
            continue
        m = re.match(r"\s*rw-human:\s*(.*)$", line, re.I)
        if not m:
            continue
        spec = m.group(1)
        v = WORD.search(spec)
        if not v:
            out.append(("error", "A 'rw-human:' line carried no verdict (approved | rejected): " + flat(line)))
            continue
        item = flat(spec[:v.start()])
        out.append(("human", "all" if item.lower() in ALL else item, VERDICTS[v.group(1).lower()], flat(spec[v.end():])))
    # The bare word: the whole message, and nothing else.
    whole = prompt.strip()
    said = whole.rstrip(".!").strip().lower()
    if said in ("aprovado", "aprovada", "approved"):
        out.append(("word", "approved", ""))
    else:
        m = re.match(r"(reprovado|reprovada|rejected)(?![^\s:,.;-])[\s:,.;-]*(.*)$", whole, re.I | re.S)
        if m:
            out.append(("word", "rejected", flat(m.group(2))))
    return out


class Refused(Exception):
    pass


def _top(d):
    r = subprocess.run(["git", "-C", d, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else ""


def apply_config(session_root, cwd, spec):
    """One `rw-config:` line, applied. Returns what was done; raises Refused, having written
    nothing, with the reason."""
    words = spec.split()
    if not words:
        raise Refused("it names no file. The form is: rw-config: [<repository>] <file> + <line>")
    repo, taken = session_root, 0
    if words[0] not in OWNER_FILES:
        if len(words) < 2 or words[1] not in OWNER_FILES:
            raise Refused("'%s' is not one of the owner's files (%s)" % (words[0], ", ".join(OWNER_FILES)))
        named = os.path.expanduser(words[0])
        named = named if os.path.isabs(named) else os.path.join(cwd, named)
        if not os.path.isdir(named):
            raise Refused("'%s' is not a directory" % words[0])
        # The repository that directory ANSWERS to, by the rule the fences use (repo_of): a nested
        # repository with no rite of its own is, to the rite, part of the one that holds it, and a
        # `.roadworthy/` written in it would take it out of a front open over it.
        sys.dont_write_bytecode = True
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from planblocks import repo_of
        repo, taken = repo_of(os.path.join(named, "x")), 1
        if not repo:
            raise Refused("'%s' is not in a git repository" % words[0])
    elif not repo or _top(repo) != os.path.realpath(repo):
        raise Refused("the session stands in no repository; name one: rw-config: <repository> <file> ...")
    name = words[taken]
    rest = spec.split(None, taken + 1)
    rest = rest[taken + 1].strip() if len(rest) > taken + 1 else ""
    path = os.path.join(repo, ".roadworthy", name)
    shown = os.path.join(repo, ".roadworthy", name)
    if not rest:
        raise Refused("it says no change for %s. The form is '+ <line>' or '- <line>'; for docs.json, '<key> = <value>'" % name)
    if name == "docs.json":
        m = re.match(r"(.+?)\s*=\s*(.*)$", rest)
        if not m or not m.group(1).strip():
            raise Refused("for docs.json the form is '<key> = <value>'")
        key, value = m.group(1).strip(), m.group(2).strip()
        data = {}
        if os.path.exists(path):
            try:
                data = json.load(open(path, encoding="utf-8"))
            except Exception:
                raise Refused("%s is not valid JSON as it stands; it was left as it is" % shown)
        if not isinstance(data, dict):
            raise Refused("%s does not hold a JSON object; it was left as it is" % shown)
        target, last = data, key
        if "." in key:
            first, last = key.split(".", 1)
            target = data.setdefault(first, {})
            if not isinstance(target, dict):
                raise Refused("'%s' in %s is not an object, so '%s' cannot go inside it" % (first, shown, last))
        try:
            parsed = json.loads(value)
        except Exception:
            parsed = value
        target[last] = parsed
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
        return "%s: %s = %s" % (shown, key, json.dumps(parsed, ensure_ascii=False))
    op, line = rest[0], rest[1:].strip()
    if op not in "+-" or not line:
        raise Refused("the form for %s is '+ <line>' to add and '- <line>' to remove" % name)
    lines = []
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().splitlines()
    if op == "-":
        if line not in lines:
            raise Refused("the line '%s' is not there in %s; nothing was changed" % (line, shown))
        lines = [l for l in lines if l != line]
        done = "%s: removed '%s'" % (shown, line)
    else:
        key = line.split(":", 1)[0].strip().lower() if name == "rites" and ":" in line else None
        if key is not None:
            # In the rites a key is set: the fences read the first line of a key.
            lines = [l for l in lines if l.strip().startswith("#") or ":" not in l
                     or l.split(":", 1)[0].strip().lower() != key]
        if line in lines:
            return "%s: '%s' was already there; nothing to change" % (shown, line)
        lines.append(line)
        done = "%s: added '%s'" % (shown, line)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("".join(l + "\n" for l in lines))
    return done


def main():
    if len(sys.argv) >= 5 and sys.argv[1] == "--apply-config":
        try:
            print(apply_config(sys.argv[2], sys.argv[3], sys.argv[4]))
            return 0
        except Refused as why:
            print(str(why))
            return 1
    for order in orders(os.environ.get("RW_PROMPT", "")):
        print("\t".join(order))
    return 0


if __name__ == "__main__":
    sys.exit(main())
