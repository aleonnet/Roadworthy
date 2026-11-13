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

A marker only counts at the START OF A LINE, and the bare word only as the whole message: in the
middle of a sentence both are conversation ("acho que está aprovado, mas...").

The limit, declared: the channel trusts the prompt the person submitted. A text the person pasted
that carries one of these lines at the start of a line is the person's order.

Output, one order per line, fields separated by tabs (a tab or a newline inside a field becomes a
space):
    human <TAB> item <TAB> approved|rejected <TAB> note
    word  <TAB> approved|rejected <TAB> note
    error <TAB> what was wrong with a line that carried a marker

Usage: ownerline.py            the prompt in the environment variable RW_PROMPT
"""
import os
import re
import sys

VERDICTS = {"approved": "approved", "aprovado": "approved", "aprovada": "approved",
            "rejected": "rejected", "reprovado": "rejected", "reprovada": "rejected"}
WORD = re.compile(r"(?<!\S)(%s)(?!\S)" % "|".join(VERDICTS), re.I)
ALL = ("", "all", "tudo", "todas", "todos")


def flat(text):
    return " ".join(text.replace("\t", " ").split())


def orders(prompt):
    out = []
    for line in prompt.splitlines():
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


def main():
    for order in orders(os.environ.get("RW_PROMPT", "")):
        print("\t".join(order))
    return 0


if __name__ == "__main__":
    sys.exit(main())
