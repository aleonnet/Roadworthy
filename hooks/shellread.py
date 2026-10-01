#!/usr/bin/env python3
"""shellread — what a shell command writes and removes, read the way the shell reads it.

Until 0.7.0 this lived inside hooks/rite-gate as forty lines that split a command on spaces. It
tracked quotes and `$( )`, and nothing else, and both of its failures were measured:

  * it saw writes that were not there. A `>=` inside the body of a heredoc, or a `>` after an
    escaped quote, became the target of a redirection, and a command that only READ was denied
    (field, 2026-09-30, twice; and three more times while this file was being planned);
  * it missed writes that were. A newline was whitespace, so a command on a second line was never
    in command position; so was anything behind `X=1`, behind `command`, inside `$( )` or inside
    `if ...; then`; `sed -i.bak` was not `-i`; and a verb's arguments were collected to the end of
    the whole line, so `cp a .roadworthy/state && true` examined the word `true`. Six of eight
    such forms aimed at the foundation of the rite went through (measured 2026-09-30) while the
    attack suite said removing the approval snapshot was refused.

So this is a reader, not a list of verbs: quoting, backslash, comments, heredoc bodies (data,
unless what consumes them is a shell), command and process substitution read from the inside,
every separator including the newline, subshells, `[[ ]]` and `(( ))`, reserved words,
assignments, wrappers (`command`, `env`, `sudo`, `xargs`...), `bash -c`, `eval` and `trap` read from
the inside, a script piped into a shell, braces and globs, and the directory in force.

AN INTERPRETER HANDED THE RITE (0.7.0). The limit above stops at the rite's own directory. Inline
code given to an interpreter -- `python3 -c`, a heredoc fed to `python3 -`, `node -e`, `perl -e`,
`ruby -e`, `awk` -- is read for one thing: does it WRITE through a path that names `.roadworthy`?
Python is parsed (the `ast` module): a string that names the directory, followed through
assignments, `+`, f-strings, `os.path.join` and `Path()`, reaching the path of a call that writes,
removes or renames. `'.road' + 'worthy/scope'` is followed; a string that merely appears in the
text being edited is not a path and is left alone (the plugin's own source is edited this way
every day). The other languages are read as text: the directory named, and a writing primitive.
A script on disk, and a name built by arithmetic, stay the declared limit.

What it emits, one per line, as KIND <TAB> DIRECTORY <TAB> PATH:
  W  a write to PATH                R  a removal of PATH
  V  PATH put back the way git has it (`git checkout -- PATH`, `git restore PATH`): a write that
     removes a difference, which is how a change outside the scope is undone
  U  a write somewhere under PATH   D  a removal somewhere under PATH
     (the target is not on the command line: `patch`, `git apply`, an unresolved variable,
     `xargs rm`)
  F  a removal under PATH that may reach the rite's own files (`find . -delete`, `git clean -x`)
  G  a removal of what git does not track under PATH (`git clean`, `git stash -u`): it reaches
     the rite's files exactly when they are untracked and not ignored, which the caller asks git
  N  PATH names the plugin's directory and is handed to a command that is not known to only read;
     or the command names that directory and writes to something this could not read (PATH is
     then the bare `.roadworthy`)
  S  skills/plan/scripts/scope-write.sh run on the plan PATH (DIRECTORY: where the front opens)
  H  a PERSON's act typed in a command: skills/close/scripts/close.sh recording an answer
     (`--human <item> approved|rejected`, PATH `human`), or scope-write.sh opening a front as the
     owner (`--owner`, PATH `owner`)
  C  a `git commit` in the repository DIRECTORY; PATH is `-` (what is staged), `-a` (every tracked
     change too) or a pathspec the commit names
  A  a `git add` in DIRECTORY, in the same command as a commit; PATH is the pathspec, or `*`
  X  the command could not be read
PATH is as written; DIRECTORY is the directory in force for it.

TWO RULES, AND WHY THERE ARE TWO. For an ordinary file the reader names what the shell itself
writes (every redirection) and what a fixed table of file-management verbs writes; a program that
opens the file itself -- an interpreter, a compiler, an editor -- writes through nothing this can
name. That is a declared limit: measured on 33,811 real commands on 2026-09-30, 25.7% use an
interpreter or a heredoc, and denying what cannot be read would deny a quarter of all work. What
backs it up is exact and lives elsewhere: the commit (hooks/guard-commit reads git's own index)
and the closing (the front's diff).
For the rite's OWN files the rule is the other way round (kind N): only a command known to read
may be handed a path under `.roadworthy`. A list of verbs that write never closes -- the first
cold review of this file found `gzip`, `sort -o`, `tar -cf` and thirty more in an afternoon -- and
a list of commands that read does.
The same rule has a second half, for what cannot be followed at all: a variable only known at run
time (`for d in .roadworthy; do rm $d/state; done`), names arriving through a pipe, a directory
changed to somewhere unknown, a command nested too deep to read. When a command writes or removes
through one of those AND names the plugin's directory anywhere in its text, it is answered with
N on the bare directory. A command that does neither is untouched.

Usage: RW_CMD='<command>' shellread.py <cwd>
Import: sys.path.insert(0, "<plugin>/hooks"); from shellread import targets
"""
import fnmatch
import glob as globlib
import os
import re
import shlex
import sys

OPS = ("&&", "||", ";;", "|&", ";", "|", "&", "(", ")")
REDIR = re.compile(r"(\d*)(&>>|&>|>>!|>>\||>>|>!|>\||>&|<<<|<<-|<<|<&|<>|>|<)")
# `<>` opens the file for writing too; `>!` and `>>!` are how zsh spells "clobber".
WRITE_REDIRS = (">", ">>", ">|", "&>", "&>>", ">!", ">>!", ">>|", "<>")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)(\[[^\]]*\])?(\+?)=")
SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
# Words after which a command still starts: the reader goes on to the next word.
PREFIX_WORDS = ("if", "then", "else", "elif", "while", "until", "do", "!", "{", "time")
# Words that end or open a construct with no command of their own on that position.
NO_COMMAND = ("fi", "done", "esac", "}", "case", "select", "in", "((", "[[", "]]")
# What may be handed a path under the plugin's own directory: commands that read, the shell's own
# tests, and the ones this file follows by name (their writes are reported as W or R).
MAY_NAME_THE_RITE = frozenset((
    "cat", "bat", "less", "more", "head", "tail", "grep", "egrep", "fgrep", "rg", "ag", "wc", "ls",
    "stat", "file", "du", "shasum", "sha256sum", "sha1sum", "md5", "md5sum", "cksum", "jq", "diff",
    "cmp", "comm", "test", "[", "echo", "printf", "cut", "awk", "sed", "sort", "uniq", "tr", "nl",
    "od", "xxd", "hexdump", "strings", "column", "python", "python3", "node", "ruby", "perl",
    "git", "find", "basename", "dirname", "realpath", "readlink", "which", "type", "cd", "pushd",
    "mkdir", "true", "false", ":", "tee", "cp", "mv", "install", "ln", "rsync", "truncate", "tar", "bsdtar",
    "touch", "dd", "rm", "unlink", "rmdir", "curl", "wget", "xargs", "export", "declare", "local",
    "typeset", "readonly", "read", "unset", "set", "tree", "fd", "exa", "eza", "tac", "rev", "fold",
    "fmt", "paste", "join", "zcat", "gzcat", "bzcat", "xzcat", "date", "sleep", "shellcheck", "yq",
    "lychee", "pwd", "seq", "expr", "wait", "exit", "return", "mktemp", "pbcopy", "popd",
) + SHELLS)
INTERPRETERS = {"python": "c", "python3": "c", "node": "ep", "deno": "e", "bun": "e", "ruby": "e", "perl": "eE",
                "php": "r", "lua": "e", "osascript": "e", "Rscript": "e", "awk": "", "gawk": "", "mawk": ""}
# What writes, removes or renames, in the languages read as text.
WRITES_TEXT = re.compile(r"writeFile|appendFile|createWriteStream|rmSync|unlink|rename|copyFile|truncate|chmod|"
                         r"File\.(?:write|open|delete|rename)|IO\.write|fopen|file_put_contents|open\s*\(|"
                         r"system\s*\(|exec\s*\(|spawn|`|(?<![=<>-])>(?![=>])|do shell script", re.I)
GLOB_CHARS = "*?["
# The names the rite keeps under its own directory: what a `find -name` could be aiming at.
RITE_NAMES = (".roadworthy", "scope", "gates", "plan.snapshot", "state", "overnight", "evidence.jsonl",
              "denials.jsonl", "refutations.jsonl", "preflight.jsonl", "readings.jsonl", "stop-latch",
              "protected", "overnight-rules", "free", "docs.json")


class Word:
    """One shell word after quote removal.

    A word is kept as PARTS -- literal text, a variable, something only known at run time -- and
    turned into text when the command it belongs to is reached, never when the line is split: a
    variable assigned earlier on the same line (`t=/tmp/x; echo > "$t"`) is known by then.
    `dynamic` means part of the word could not be resolved; `bare` records that an unquoted part
    carries a glob or a brace, which the shell would expand; `split` that an unquoted variable
    was resolved, which the shell would split into words."""
    __slots__ = ("parts", "text", "dynamic", "subs", "tilde", "proc", "prefix", "tail", "flat", "bare", "split")

    def __init__(self, text="", dynamic=False, subs=None, tilde=False, proc=False):
        self.parts = ([("l", text, True)] if text else []) + ([("d",)] if dynamic else [])
        self.text, self.dynamic, self.subs, self.tilde = text, dynamic, subs or [], tilde
        self.proc = proc                            # `<( )` or `>( )`: a pipe, never a file
        self.prefix = ""                            # the text before the first unresolved part
        self.tail = ""                              # the text after the last one
        self.flat = list(self.parts)                # the parts with every known variable spelled out
        self.bare = False
        self.split = False

    def add(self, parts):
        for part in parts:
            last = self.parts[-1] if self.parts else None
            if part[0] == "l" and last and last[0] == "l" and last[2] == part[2]:
                self.parts[-1] = ("l", last[1] + part[1], part[2])
            else:
                self.parts.append(part)

    def resolve(self, env):
        # A variable holds text, or -- when what it was assigned was only partly known -- parts of
        # its own: `H="docs/plans/$(date +%H%M)-handoff.md"` is under docs/plans and ends in
        # `-handoff.md`, and `> "$H"` is known to be exactly that much.
        flat, split = [], False

        def walk(parts, depth):
            nonlocal split
            for part in parts:
                value = env.get(part[1]) if part[0] in ("v", "vd") else None
                if part[0] == "l":
                    flat.append(part)
                elif isinstance(value, str) and (value or part[0] == "v"):
                    flat.append(("l", value, True))
                    split = split or (part[0] == "v" and not part[2])
                elif isinstance(value, list) and depth < 8:
                    walk(value, depth + 1)
                elif part[0] == "vd":
                    flat.append(("l", part[2], True))
                else:
                    flat.append(("d",))

        walk(self.parts, 0)
        text, dynamic, prefix, tail, bare = "", False, None, "", False
        for part in flat:
            if part[0] == "l":
                text += part[1]
                tail += part[1]
                if not part[2] and any(ch in part[1] for ch in GLOB_CHARS + "{"):
                    bare = True
            else:
                if prefix is None:
                    prefix = text
                dynamic, tail = True, ""
        self.text, self.dynamic, self.prefix, self.tail = text, dynamic, (prefix or ""), tail
        self.flat, self.bare, self.split = flat, bare, split
        return self

    def value_after(self, cut):
        """The parts of this word after its first `cut` characters: the value of `NAME=...`."""
        out = []
        for part in self.flat:
            if part[0] == "l" and cut:
                if len(part[1]) <= cut:
                    cut -= len(part[1])
                    continue
                part, cut = ("l", part[1][cut:], True), 0
            out.append(part)
        return out


def _names_rite(text, here):
    """Whether a word is a PATH into the plugin's directory. Prose that mentions it is not one:
    `--decision "the guard denies while .roadworthy/overnight exists"` was an N on 12 of the 55
    real commands the first measurement of this rule flagged (2026-09-30)."""
    m = re.search(r"\.roadworthy(?:/|$)", text, re.I)
    if not m:
        return False
    if not re.search(r"[\s\"'{}<>|;]", text):
        return True
    return os.path.isdir(here(text[:m.end()].rstrip("/")))


def _could_name_rite(word):
    """Whether a word only partly known could still be one of the rite's files. What is known of
    it is its end: `"$d/plan.snapshot"` and `"$x"` could, `"docs/$stamp-handoff.md"` could not."""
    tail = word.tail
    if ".roadworthy" in tail.lower() or ".roadworthy" in word.prefix.lower():
        return True
    if "/" in tail:
        base = tail.rsplit("/", 1)[1]
        return base == "" or base in RITE_NAMES
    return tail == "" or any(n.endswith(tail) for n in RITE_NAMES)


def _heredoc_open(s, i):
    """At s[i:] == `<<` (not `<<<`): (delimiter, strip tabs, index after the delimiter)."""
    j = i + 2
    strip = s.startswith("-", j)
    if strip:
        j += 1
    while j < len(s) and s[j] in " \t":
        j += 1
    k = j
    while k < len(s) and s[k] not in " \t\n;&|<>()":
        k += 2 if s[k] == "\\" else 1
    return re.sub(r"[\\'\"]", "", s[j:k]), strip, k


def _close(s, i, open_ch="(", close_ch=")"):
    """Index of the bracket that closes the one opened just before s[i]. Quotes are respected, and
    so are heredoc bodies: a quote inside one belongs to the data, not to the command."""
    depth, n, pending = 1, len(s), []
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            i = (n if j == -1 else j) + 1
            continue
        if c == '"':
            i = _dq_end(s, i + 1) + 1
            continue
        if c == "`":
            i = _bt_end(s, i + 1) + 1
            continue
        if c == "<" and open_ch == "(" and s.startswith("<<", i) and not s.startswith("<<<", i):
            delim, strip, i = _heredoc_open(s, i)
            if delim:
                pending.append((delim, strip))
            continue
        if c == "\n" and pending:
            i += 1
            for delim, strip in pending:
                _, i = _heredoc(s, i, delim, strip)
            pending = []
            continue
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _arith_end(s, i):
    """Index of the `))` that closes an arithmetic expression opened just before s[i], or -1 when
    what was opened is not arithmetic at all but two subshells: `((echo a); rm x)`."""
    depth, n = 0, len(s)
    while i < n:
        c = s[i]
        if c == "(":
            depth += 1
        elif c == ")":
            if depth == 0:
                return i if s.startswith("))", i) else -1
            depth -= 1
        elif c in ";\n`":
            return -1                               # a command separator: these were subshells
        elif c == "$" and s.startswith("$(", i) and not s.startswith("$((", i):
            i = _close(s, i + 2)                    # a command substitution inside the expression
        i += 1
    return -1


def _dq_end(s, i):
    """Index of the double quote that closes the one opened just before s[i]."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "$" and s.startswith("$(", i) and not (s.startswith("$((", i) and _arith_end(s, i + 3) != -1):
            i = _close(s, i + 2) + 1
            continue
        if c == "`":
            i = _bt_end(s, i + 1) + 1
            continue
        if c == '"':
            return i
        i += 1
    return n


def _bt_end(s, i):
    n = len(s)
    while i < n:
        if s[i] == "\\":
            i += 2
            continue
        if s[i] == "`":
            return i
        i += 1
    return n


def _ansi_c(text):
    """The string a `$'...'` spells: `$'st\\x61te'` is `state`."""
    try:
        return text.encode("latin-1", "backslashreplace").decode("unicode_escape")
    except Exception:
        return text


def _dollar(s, i, quoted):
    """An expansion starting at s[i] (`$` or a backtick): (parts, subs, next index)."""
    n = len(s)
    if s[i] == "`":
        j = _bt_end(s, i + 1)
        return [("d",)], [s[i + 1:j]], j + 1
    if s.startswith("$((", i):
        j = _arith_end(s, i + 3)
        if j != -1:
            return [("d",)], [], j + 2
        j = _close(s, i + 2)                        # `$( (subshell); command )`
        return [("d",)], [s[i + 2:j]], j + 1
    if s.startswith("$(", i):
        j = _close(s, i + 2)
        return [("d",)], [s[i + 2:j]], j + 1
    if s.startswith("$[", i):                       # the old spelling of arithmetic
        j = _close(s, i + 2, "[", "]")
        return [("d",)], [], j + 1
    if s.startswith("${", i):
        j = _close(s, i + 2, "{", "}")
        inner = s[i + 2:j]
        if NAME.fullmatch(inner):
            return [("v", inner, quoted)], [], j + 1
        m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*):?[-=]([^$`\\\"']*)", inner)
        if m:                                       # ${NAME:-default}: the value, or the default
            return [("vd", m.group(1), m.group(2))], [], j + 1
        return [("d",)], [], j + 1
    if s.startswith("$'", i) and not quoted:        # $'...' is a quoted string, not an expansion
        j = i + 2
        while j < n and s[j] != "'":
            j += 2 if s[j] == "\\" else 1
        return [("l", _ansi_c(s[i + 2:j]), True)], [], j + 1
    m = NAME.match(s, i + 1)
    if m:
        return [("v", m.group(0), quoted)], [], m.end()
    if i + 1 < n and (s[i + 1].isdigit() or s[i + 1] in "?!$#*@-"):
        return [("d",)], [], i + 2
    return [("l", "$", True)], [], i + 1


def _dq_parts(inner):
    """The parts of a double-quoted string: (parts, subs)."""
    parts, subs, i, n = [], [], 0, len(inner)
    while i < n:
        c = inner[i]
        if c == "\\" and i + 1 < n:
            if inner[i + 1] in '"\\$`':
                parts.append(("l", inner[i + 1], True))
            elif inner[i + 1] != "\n":
                parts.append(("l", c + inner[i + 1], True))
            i += 2
            continue
        if c in "$`":
            ps, sb, i = _dollar(inner, i, True)
            parts += ps
            subs += sb
            continue
        parts.append(("l", c, True))
        i += 1
    return parts, subs


def _word(s, i):
    """Read one word starting at s[i]: (Word, next index)."""
    n = len(s)
    w = Word(tilde=(s[i] == "~"))
    while i < n:
        c = s[i]
        if c == "\\":
            if i + 1 < n and s[i + 1] != "\n":
                w.add([("l", s[i + 1], True)])
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            j = n if j == -1 else j
            w.add([("l", s[i + 1:j], True)])
            i = j + 1
            continue
        if c == '"':
            j = _dq_end(s, i + 1)
            ps, sb = _dq_parts(s[i + 1:j])
            w.add(ps)
            w.subs += sb
            i = j + 1
            continue
        if c in "$`":
            ps, sb, i = _dollar(s, i, False)
            w.add(ps)
            w.subs += sb
            continue
        if c in " \t\n;&|<>()":
            break
        w.add([("l", c, False)])
        i += 1
    return w.resolve({}), i


def _heredoc(s, i, delim, strip):
    """The body of a heredoc starting at s[i]: (body, index after its terminator line)."""
    n, start = len(s), i
    while i < n:
        j = s.find("\n", i)
        line = s[i:(n if j == -1 else j)]
        if (line.lstrip("\t") if strip else line) == delim:
            return s[start:i], (n if j == -1 else j + 1)
        if j == -1:
            break
        i = j + 1
    return s[start:], n


def _test_end(s, i):
    """Index just after the `]]` that closes a `[[` opened before s[i], or -1."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            i = (n if j == -1 else j) + 1
            continue
        if c == '"':
            i = _dq_end(s, i + 1) + 1
            continue
        if s.startswith("]]", i) and s[i - 1] in " \t\n" and (i + 2 >= n or s[i + 2] in " \t\n;&|<>()"):
            return i + 2
        i += 1
    return -1


def tokenize(s):
    """Tokens of a command: ("W", Word) | ("O", operator) |
    ("R", op, fd, Word, heredoc body, whether the heredoc delimiter was quoted)."""
    toks, i, n, pending = [], 0, len(s), []
    while i < n:
        c = s[i]
        if c in " \t":
            i += 1
            continue
        if c == "\\" and i + 1 < n and s[i + 1] == "\n":
            i += 2
            continue
        if c == "\n":
            toks.append(("O", "\n"))
            i += 1
            for index, delim, strip in pending:     # the bodies follow the line that opened them
                body, i = _heredoc(s, i, delim, strip)
                toks[index] = toks[index][:4] + (body, toks[index][5])
            pending = []
            continue
        if c == "#":                                # only ever reached at the start of a word
            j = s.find("\n", i)
            i = n if j == -1 else j
            continue
        at_command = not toks or toks[-1][0] == "O" or (toks[-1][0] == "W" and toks[-1][1].text in PREFIX_WORDS)
        if at_command and s.startswith("[[", i) and i + 2 < n and s[i + 2] in " \t\n":
            j = _test_end(s, i + 2)
            if j != -1:                             # everything inside `[[ ]]` is a test, not shell
                toks.append(("W", Word("[[")))
                i = j
                continue
        if c in "<>" and s.startswith("(", i + 1):  # process substitution: its inside is a command
            j = _close(s, i + 2)
            toks.append(("W", Word(dynamic=True, subs=[s[i + 2:j]], proc=True)))
            i = j + 1
            continue
        if s.startswith("((", i):
            j = _arith_end(s, i + 2)
            if j != -1:                             # (( arithmetic )): a `>` inside is no redirection
                toks.append(("W", Word("((")))
                i = j + 2
                continue
        m = REDIR.match(s, i)
        if m:
            op, i = m.group(2), m.end()
            while i < n and s[i] in " \t":
                i += 1
            start = i
            if i < n and s[i] not in "\n;&|<>()":
                target, i = _word(s, i)
            else:
                target = None
            if op in ("<<", "<<-") and target is not None:
                pending.append((len(toks), target.text, op == "<<-"))
            quoted = any(ch in s[start:i] for ch in "'\"\\")
            toks.append(("R", op, m.group(1), target, None, quoted))
            continue
        for op in OPS:
            if s.startswith(op, i):
                toks.append(("O", op))
                i += len(op)
                break
        else:
            w, i = _word(s, i)
            toks.append(("W", w))
    return toks


def _braces(text):
    """What the shell makes of `a{b,c}d`: every alternative, in order. A brace with no comma is
    literal, as it is to the shell."""
    start = text.find("{")
    while start != -1:
        depth, commas = 0, []
        for j in range(start, len(text)):
            ch = text[j]
            if ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    if not commas:
                        break
                    cuts = [start] + commas + [j]
                    out = []
                    for a, b in zip(cuts, cuts[1:]):
                        for mid in _braces(text[a + 1:b]):
                            for tail in _braces(text[j + 1:]):
                                out.append(text[:start] + mid + tail)
                    return out
            elif ch == "," and depth == 1:
                commas.append(j)
        start = text.find("{", start + 1)
    return [text]


def _plain(args, with_value=()):
    """The operands among `args`: no options, no values of the options listed, `--` honoured."""
    out, skip, literal = [], False, False
    for a in args:
        t = a.text
        if skip:
            skip = False
            continue
        if not literal and t == "--":
            literal = True
            continue
        if not literal and t.startswith("-") and len(t) > 1 and not a.dynamic:
            if t in with_value:
                skip = True
            continue
        out.append(a)
    return out


def _cluster(args, with_value):
    """Short options the way getopt reads them: (letter, value Word or None) for each. In
    `-so file` the `o` takes the next word; in `-ofile` it takes the rest of its own."""
    found, i = [], 0
    while i < len(args):
        t = args[i].text
        if t == "--":
            break
        if t.startswith("-") and not t.startswith("--") and len(t) > 1 and not args[i].dynamic:
            j = 1
            while j < len(t):
                ch = t[j]
                if ch in with_value:
                    if j + 1 < len(t):
                        found.append((ch, Word(t[j + 1:], tilde=t[j + 1:j + 2] == "~")))
                    elif i + 1 < len(args):
                        found.append((ch, args[i + 1]))
                        i += 1
                    break
                found.append((ch, None))
                j += 1
        i += 1
    return found


def _strip_options(args, with_value):
    """What follows a wrapper's own options: the command it runs and that command's arguments."""
    i = 0
    while i < len(args):
        t = args[i].text
        if t == "--":
            return args[i + 1:]
        if t.startswith("-") and len(t) > 1 and not args[i].dynamic:
            i += 2 if t in with_value else 1
            continue
        break
    return args[i:]


def _env(env, name, default):
    """A variable as text; one only partly known is not known."""
    value = env.get(name)
    return value if isinstance(value, str) and value else default


def _path(word, env):
    if word.tilde and (word.text == "~" or word.text.startswith("~/")):
        return _env(env, "HOME", "~") + word.text[1:]
    return word.text


def _known_dir(word, env, cwd):
    """The directory a word only partly known is certainly under: `/tmp/run/$i/out` is under
    /tmp/run, `lib/$f` is under lib, `$x` is under nothing but the directory in force."""
    prefix = word.prefix
    if word.tilde and (prefix == "~" or prefix.startswith("~/")):
        prefix = _env(env, "HOME", "~") + prefix[1:]
    if "/" not in prefix:
        return cwd
    return prefix[:prefix.rindex("/")] or "/"


def _base_env(cwd):
    # The hook runs in the environment the harness gives the shell tool, so a variable the command
    # reads from it (the session scratchpad, a job directory) is known here too. What the command
    # assigns itself overrides it, as it does in the shell.
    env = {k: v for k, v in os.environ.items() if v}
    for k in ("HOME", "TMPDIR"):
        if env.get(k):
            env[k] = env[k].rstrip("/") or "/"
    env["PWD"] = cwd
    return env


def targets(cmd, cwd, env=None, depth=0, state=None):
    """Every write and removal a command names: a list of (kind, directory, path). It never
    raises: what it cannot read it says so, as kind X."""
    if depth > 8:
        return [("X", cwd, cwd)]
    try:
        found = _targets(cmd, cwd, env, depth, state)
    except RecursionError:
        found = [("X", cwd, cwd)]
    except Exception:
        if depth:
            raise
        found = [("X", cwd, cwd)]
    if depth:
        return found
    # `B` never leaves this file: it marks a write or a removal whose target could not be followed,
    # and carries the directory that target is certainly under, when one is known. In a command
    # that names the plugin's directory it becomes an N on that directory's `.roadworthy` -- so a
    # toy repository under the session scratchpad (`R="$S/toy-$$"; echo x > "$R/.roadworthy/scope"`,
    # 16 of the 24 real commands this rule flagged on 2026-09-30) is still judged by where it is.
    blind = [(d, p) for kind, d, p in found if kind == "B"] + [(d, "") for kind, d, _ in found if kind == "X"]
    found = [t for t in found if t[0] != "B"]
    if blind and ".roadworthy" in cmd.lower():
        for d, known in dict.fromkeys(blind):
            found.append(("N", d, (known.rstrip("/") + "/.roadworthy") if known else ".roadworthy"))
    return found


def _targets(cmd, cwd, env, depth, state):
    out = []
    if env is None:
        env = _base_env(cwd)
    elif state is None:
        env = dict(env)                             # a subshell: its assignments stay in it
    if state is None:
        state = {"cwd": cwd, "old": cwd, "dirs": [], "lost": False}
    pipeline, cur, stack = [], [], []
    for tok in tokenize(cmd) + [("O", "\n")]:
        if tok[0] != "O":
            cur.append(tok)
            continue
        pipeline.append(cur)
        cur = []
        if tok[1] in ("|", "|&"):
            continue
        _pipeline(pipeline, state, env, out, depth)
        pipeline = []
        if tok[1] == "(":                           # a subshell keeps its `cd` to itself
            stack.append(state["cwd"])
        elif tok[1] == ")" and stack:
            state["cwd"] = stack.pop()
    return out


def _pipeline(pipeline, state, env, out, depth):
    """The commands joined by `|`. Two things only make sense across the pipe: a script piped into
    a shell, and names piped into `xargs`."""
    parsed = [_parse(cur, state, env, out, depth) for cur in pipeline]
    for i, p in enumerate(parsed):
        if p is None:
            continue
        fed = None
        bare_shell = p["name"] in SHELLS and p["script"] is None and (not _plain(p["args"], ("-o", "-O")) or "-s" in [a.text for a in p["args"]])
        if i > 0 and p["name"] in INTERPRETERS:      # code piped into an interpreter is its program
            prev = parsed[i - 1]
            if prev and prev["name"] in ("echo", "printf") and not any(a.dynamic for a in prev["args"]):
                fed = " ".join(a.text for a in prev["args"])
            elif prev and prev["body"] is not None:
                fed = prev["body"]
        if i > 0 and bare_shell:
            prev = parsed[i - 1]
            if prev and prev["name"] in ("echo", "printf") and not any(a.dynamic for a in prev["args"]):
                fed = " ".join(a.text for a in prev["args"])
            elif prev and prev["body"] is not None:
                fed = prev["body"]
            else:
                out.append(("U", state["cwd"], state["cwd"]))   # a shell fed something unknown
                out.append(("B", state["cwd"], ""))
        _simple(p, state, env, out, depth, fed)
        # `find . -name state | xargs rm`: the names are find's, the removal is xargs's.
        if p["via_xargs"] and p["name"] in ("rm", "unlink", "rmdir", "mv", "shred"):
            cwd = state["cwd"]
            here = lambda path: path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))
            for q in parsed[:i]:
                if q and q["name"] == "find":
                    roots, reaches = _find_reach(q["args"], [a.text for a in q["args"]])
                    for r in (roots or [Word(".")]):
                        out.append(("F" if reaches else "D", cwd, cwd if r.dynamic else here(_path(r, env))))
    # `echo .roadworthy/plan.snapshot | xargs rm`: the names travel through the pipe.
    if any(p and p["via_xargs"] and p["name"] not in ("cat", "grep", "wc", "ls", "head", "tail", "echo", "stat", "file", "shasum", "basename", "dirname", "sort", "du", "sed", "awk", "jq", "sh", "bash") for p in parsed):
        cwd = state["cwd"]
        here = lambda path: path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))
        for p in parsed:
            if p:
                for w in p["words"]:
                    if _names_rite(w.text, here):
                        out.append(("N", cwd, w.text))


def _parse(cur, state, env, out, depth):
    """One simple command: words made into text, assignments recorded, wrappers peeled."""
    cwd = state["cwd"]
    words = [t[1].resolve(env) for t in cur if t[0] == "W"]
    redirs = [t for t in cur if t[0] == "R"]
    for r in redirs:
        if r[3] is not None and r[1] not in ("<<", "<<-"):
            r[3].resolve(env)
    # Substitutions run first, in a subshell of their own.
    for w in words + [r[3] for r in redirs if r[3] is not None]:
        for sub in w.subs:
            out.extend(targets(sub, cwd, env, depth + 1))
    # Braces make several words of one, before anything reads them.
    expanded = []
    for w in words:
        if w.bare and "{" in w.text and not w.dynamic:
            alts = _braces(w.text)
            if len(alts) > 1:
                for alt in alts:
                    nw = Word(alt, tilde=w.tilde)
                    nw.bare = any(ch in alt for ch in GLOB_CHARS)
                    expanded.append(nw)
                continue
        expanded.append(w)
    words = expanded

    k = 0
    while k < len(words):
        t = words[k].text
        m = ASSIGN.match(t)
        if m and not words[k].tilde:
            w = words[k]
            if not w.dynamic and not m.group(2) and not m.group(3):
                value = t[m.end():]
                if value == "~" or value.startswith("~/"):      # the shell expands it after the `=`
                    value = _env(env, "HOME", "~") + value[1:]
                env[m.group(1)] = value
            elif len(w.subs) == 1 and re.match(r"\s*mktemp\b", w.subs[0]) and t[m.end():] == "":
                # `x="$(mktemp)"` is a path under the temporary directory, whatever its name.
                env[m.group(1)] = _env(env, "TMPDIR", "/tmp").rstrip("/") + "/mktemp.unknown"
            elif not m.group(2) and not m.group(3):
                env[m.group(1)] = w.value_after(m.end())    # partly known: kept as parts
            else:
                env.pop(m.group(1), None)
            k += 1
        elif t in PREFIX_WORDS and not words[k].dynamic:
            k += 1
            if t == "time" and k < len(words) and words[k].text == "-p":
                k += 1
        elif t == "function" and not words[k].dynamic:
            k += 2                                  # `function NAME`: the body follows
        elif t == "for" and not words[k].dynamic:
            if k + 1 < len(words):
                env.pop(words[k + 1].text, None)    # the loop variable is anything from here on
            k = len(words)
        else:
            break
    name = ""
    unknown = k < len(words) and words[k].dynamic   # `$tool file`: what runs is not known here
    if k < len(words) and not words[k].dynamic and words[k].text not in NO_COMMAND:
        if words[k].split and len(words[k].text.split()) > 1:
            # `c="rm x"; $c`: the shell splits an unquoted variable, and its first word is the command.
            rest = " ".join(shlex.quote(a.text) for a in words[k + 1:] if not a.dynamic)
            out.extend(targets(words[k].text + " " + rest, cwd, env, depth + 1))
            return None
        name = os.path.basename(words[k].text)
    args = words[k + 1:] if name else []
    via_xargs = False
    # Wrappers hand the rest of the line to another command.
    while name:
        if name in ("command", "builtin", "exec", "nohup", "noglob", "nocorrect", "coproc", "-"):
            rest = _strip_options(args, ("-a",))
        elif name == "stdbuf":
            rest = _strip_options(args, ("-i", "-o", "-e"))
        elif name == "nice":
            rest = _strip_options(args, ("-n",))
        elif name == "timeout":
            rest = _strip_options(args, ("-s", "-k", "--signal", "--kill-after"))[1:]
        elif name == "sudo":
            rest = _strip_options(args, ("-u", "-g", "-C", "-D", "-h", "-p", "-R", "-T", "-U"))
        elif name == "env":
            rest = _strip_options(args, ("-u", "-C", "-S"))
            while rest and ASSIGN.match(rest[0].text):
                rest = rest[1:]
        elif name == "xargs":
            rest = _strip_options(args, ("-I", "-n", "-P", "-L", "-s", "-d", "-E", "-a", "-J", "-R"))
            via_xargs = True
            # `xargs -I{} cp {} {}.orig`: the placeholder is a name only known when it runs.
            holder = next((args[i + 1].text for i, a in enumerate(args[:-1]) if a.text in ("-I", "-J")), None)
            holder = holder or next((a.text[2:] for a in args if a.text.startswith("-I") and len(a.text) > 2), None)
            if holder:
                for w in rest:
                    if holder in w.text and not w.dynamic:
                        w.prefix, w.tail = w.text.split(holder, 1)[0], w.text.rsplit(holder, 1)[1]
                        w.dynamic = True
        else:
            break
        if not rest or rest[0].dynamic:
            name, args, unknown = "", [], bool(rest)
            break
        name, args = os.path.basename(rest[0].text), rest[1:]
    body = None
    for r in redirs:
        if r[1] in ("<<", "<<-") and r[4] is not None:
            body = r[4]
    script = None
    if name in SHELLS:
        for letter, value in _cluster(args, "cOo"):
            if letter == "c" and value is not None:
                script = value
    return {"words": words, "redirs": redirs, "name": name, "args": args, "via_xargs": via_xargs,
            "body": body, "script": script, "unknown": unknown}


def _simple(p, state, env, out, depth, fed=None):
    words, redirs, name, args, via_xargs = p["words"], p["redirs"], p["name"], p["args"], p["via_xargs"]
    cwd = state["cwd"]
    here = lambda path: path if os.path.isabs(path) else os.path.normpath(os.path.join(cwd, path))
    named = set()

    def emit(kind, word):
        """W or R on a word. A word only known at run time becomes U or D on the directory it is
        certainly under; a glob becomes every file it matches, as it does to the shell."""
        if not isinstance(word, Word):
            word = Word(word)
        if word.proc:
            return
        if word.dynamic or not word.text:
            out.append(("U" if kind == "W" else "D", cwd, _known_dir(word, env, cwd)))
            if _could_name_rite(word):
                out.append(("B", cwd, _known_dir(word, env, "")))
            return
        path = _path(word, env)
        named.add(word.text)
        if state["lost"] and not os.path.isabs(path):
            out.append(("B", cwd, ""))              # relative to a directory this could not follow
        if word.bare and any(ch in path for ch in GLOB_CHARS):
            matches = sorted(globlib.glob(here(path)))
            for match in matches:
                out.append((kind, cwd, match))
            if matches:
                return
        out.append((kind, cwd, path))

    for _, op, _fd, target, body, quoted in redirs:
        if op in ("<<", "<<-") and body is not None and not quoted:
            # An unquoted heredoc is expanded before it is fed: `$( )` inside it runs.
            for sub in _dq_parts(body)[1]:
                out.extend(targets(sub, cwd, env, depth + 1))
        if target is None:
            continue
        if op in WRITE_REDIRS:
            emit("W", target)
        elif op == ">&" and not target.dynamic and not re.fullmatch(r"\d+|-", target.text or "0"):
            emit("W", target)                       # `>&file` is `&>file`; `>&2` and `>&$fd` are not
        elif op == "<<<" and name in SHELLS and not target.dynamic and p["script"] is None:
            out.extend(targets(target.text, cwd, env, depth + 1))
    if not name:
        if p["unknown"]:                            # not known to only read, because not known at all
            for w in words:
                if _names_rite(w.text, here):
                    out.append(("N", cwd, _path(w, env)))
        return

    texts = [a.text for a in args]
    if name in SHELLS:
        if p["script"] is not None:
            # A script only known at run time is not read: denying `bash -c "$x"` would deny every
            # `eval "$(tool init -)"` on earth. Its substitutions were already read in _parse.
            if not p["script"].dynamic:
                out.extend(targets(p["script"].text, cwd, env, depth + 1))
            return
        ops = _plain(args, ("-o", "-O"))
        reads_stdin = not ops or "-s" in texts
        if reads_stdin and fed is not None:
            out.extend(targets(fed, cwd, env, depth + 1))       # the script came through the pipe
        elif reads_stdin and p["body"] is not None:
            out.extend(targets(p["body"], cwd, env, depth + 1)) # a shell reading a heredoc runs it
        if ops and os.path.basename(ops[0].text) == "scope-write.sh":
            _scope_write(args[args.index(ops[0]) + 1:], cwd, env, out, here)
        if ops and os.path.basename(ops[0].text) == "close.sh":
            _close_script(texts, cwd, out)
        return
    if name == "scope-write.sh":
        _scope_write(args, cwd, env, out, here)
        return
    if name == "close.sh":
        _close_script(texts, cwd, out)
        return
    if name in INTERPRETERS or re.fullmatch(r"python3?\.\d+", name):
        _interpreter(name, args, p["body"], fed, cwd, out)
    if name == "eval":
        if not any(a.dynamic for a in args):        # eval runs HERE: a `cd` inside it stays
            out.extend(targets(" ".join(texts), cwd, env, depth + 1, state))
        return
    if name == "trap":
        ops = _plain(args)
        if ops and not ops[0].dynamic and ops[0].text not in ("-", ""):
            out.extend(targets(ops[0].text, cwd, env, depth + 1))
        return
    if name in ("cd", "pushd", "popd"):
        ops = _plain(args)
        if name == "popd":
            if state["dirs"]:
                state["cwd"] = state["dirs"].pop()
        elif ops and not ops[0].dynamic and ops[0].text != "-":
            if name == "pushd":
                state["dirs"].append(cwd)
            state["old"], state["cwd"] = cwd, here(_path(ops[0], env))
        elif [a.text for a in args] == ["-"]:
            state["old"], state["cwd"] = cwd, state["old"]
        elif not args and name == "cd":
            state["old"], state["cwd"] = cwd, _env(env, "HOME", cwd)
        elif args:
            state["lost"] = True                    # `cd "$somewhere"`: from here on, unknown
        return
    # What a command may set without this reader seeing the value: from here on the variable is
    # unknown, never the stale value an earlier line gave it.
    if name in ("declare", "local", "export", "typeset", "readonly"):
        for a in args:
            m = ASSIGN.match(a.text)
            if m:
                if a.dynamic:
                    env.pop(m.group(1), None)
                else:
                    env[m.group(1)] = a.text[m.end():]
        return
    if name in ("read", "unset", "getopts", "mapfile", "readarray"):
        for a in _plain(args, ("-p", "-t", "-n", "-N", "-d", "-u", "-a", "-i", "-O", "-s", "-C", "-c")):
            env.pop(a.text, None)
        return
    if name == "printf" and "-v" in texts and texts.index("-v") + 1 < len(texts):
        env.pop(texts[texts.index("-v") + 1], None)

    if via_xargs and name in ("rm", "unlink", "rmdir", "mv", "shred"):
        out.append(("D", cwd, cwd))                 # the names arrive on standard input
        out.append(("B", cwd, ""))
    if via_xargs and (name in ("cp", "mv", "tee", "touch", "install", "truncate")
                      or (name == "sed" and _sed_in_place(texts))
                      or (name == "perl" and any(_perl_in_place(t) for t in texts))):
        out.append(("U", cwd, cwd))
        out.append(("B", cwd, ""))

    if name == "tee":
        for a in _plain(args):
            emit("W", a)
    elif name in ("cp", "install", "ln", "rsync"):
        dry = name == "rsync" and any(t == "--dry-run" or re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", t) for t in texts)
        dest = [a for i, a in enumerate(args[1:], 1) if args[i - 1].text in ("-t", "--target-directory")]
        dest += [Word(a.text.split("=", 1)[1]) for a in args if a.text.startswith("--target-directory=")]
        ops = _plain(args, ("-t", "--target-directory", "-m", "-o", "-g", "-S", "-e"))
        if dry:
            pass
        elif dest:
            emit("W", dest[0])
        elif len(ops) >= 2:
            emit("W", ops[-1])
        if name == "ln":
            # A link INTO the rite's directory is a second name for it, and the next command would
            # write through a path that never says `.roadworthy`.
            for a in (ops[:-1] if len(ops) >= 2 else ops):
                if _names_rite(a.text, here):
                    out.append(("N", cwd, _path(a, env)))
    elif name == "mv":
        dest = [a for i, a in enumerate(args[1:], 1) if args[i - 1].text in ("-t", "--target-directory")]
        dest += [Word(a.text.split("=", 1)[1]) for a in args if a.text.startswith("--target-directory=")]
        ops = _plain(args, ("-t", "--target-directory", "-S"))
        if dest:                                    # `mv -t DIR a b`: every operand leaves
            for a in ops:
                emit("R", a)
            emit("W", dest[0])
        elif len(ops) >= 2:
            for a in ops[:-1]:
                emit("R", a)
            emit("W", ops[-1])
    elif name == "truncate":
        for a in _plain(args, ("-s", "-r", "--size", "--reference")):
            emit("W", a)
    elif name == "touch":
        for a in _plain(args, ("-d", "-t", "-r", "--date", "--reference")):
            emit("W", a)
    elif name == "dd":
        for a in args:
            if a.text.startswith("of="):
                emit("W", Word(a.text[3:], a.dynamic, tilde=a.text[3:4] == "~"))
    elif name == "sed":
        if _sed_in_place(texts):
            for a in _sed_files(args):
                emit("W", a)
    elif name == "perl":
        if any(_perl_in_place(t) for t in texts):
            for a in _perl_files(args):
                emit("W", a)
    elif name in ("rm", "unlink", "rmdir"):
        for a in _plain(args):
            emit("R", a)
    elif name == "sort":
        for letter, value in _cluster(args, "okStT"):
            if letter == "o" and value is not None:
                emit("W", value)
        for a in args:
            if a.text.startswith("--output="):
                emit("W", Word(a.text.split("=", 1)[1]))
    elif name in ("gzip", "gunzip", "bzip2", "bunzip2", "xz", "unxz", "zstd", "compress", "uncompress"):
        letters = "".join(t[1:] for t in texts if t.startswith("-") and not t.startswith("--"))
        if not any(ch in letters for ch in "clt") and not any(t in ("--stdout", "--list", "--test", "--to-stdout") for t in texts):
            for a in _plain(args, ("-S", "--suffix")):
                emit("R", a)                        # the file is replaced by its compressed twin
    elif name == "curl":
        for letter, value in _cluster(args, "oDXHduAebcFmwTxrKE"):
            if letter in "oD" and value is not None and value.text != "-":
                emit("W", value)
            elif letter == "O":
                out.append(("U", cwd, cwd))         # the remote name, in the directory in force
        for i, a in enumerate(args):
            if a.text in ("--output", "--dump-header") and i + 1 < len(args) and args[i + 1].text != "-":
                emit("W", args[i + 1])
            elif a.text.startswith(("--output=", "--dump-header=")):
                emit("W", Word(a.text.split("=", 1)[1]))
            elif a.text == "--remote-name":
                out.append(("U", cwd, cwd))
    elif name == "wget":
        named_out = False
        for letter, value in _cluster(args, "OoaPUeQtTw"):
            if letter == "O" and value is not None:
                named_out = True
                if value.text != "-":
                    emit("W", value)
        for i, a in enumerate(args):
            if a.text == "--output-document" and i + 1 < len(args):
                named_out = True
                if args[i + 1].text != "-":
                    emit("W", args[i + 1])
            elif a.text.startswith("--output-document="):
                named_out = True
                if a.text.split("=", 1)[1] != "-":
                    emit("W", Word(a.text.split("=", 1)[1]))
        if not named_out and "--spider" not in texts:
            out.append(("U", cwd, cwd))
    elif name == "patch":
        if "--dry-run" not in texts:
            d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text in ("-d", "--directory")]
            out.append(("U", cwd, here(_path(d[0], env)) if d and not d[0].dynamic else cwd))
    elif name in ("tar", "bsdtar"):
        _tar(args, texts, cwd, env, out, here, emit)
    elif name == "unzip":
        letters = "".join(t[1:] for t in texts if t.startswith("-") and not t.startswith("--"))
        if not any(ch in letters for ch in "ltpvZz"):
            d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text == "-d"]
            out.append(("U", cwd, here(_path(d[0], env)) if d and not d[0].dynamic else cwd))
    elif name == "find":
        _find(args, texts, cwd, env, out, here)
    elif name == "git":
        _git(args, cwd, env, out, here)

    # THE OTHER RULE: a path under the plugin's own directory, handed to a command that is not
    # known to only read. `gzip .roadworthy/state`, an editor, a tool with `-out`: whatever it is,
    # it has no business there.
    if name not in MAY_NAME_THE_RITE:
        for w in words:
            if _names_rite(w.text, here) and w.text not in named:
                out.append(("N", cwd, _path(w, env)))
            elif w.bare and not w.dynamic and any(ch in w.text for ch in GLOB_CHARS):
                for match in globlib.glob(here(_path(w, env))):
                    if "/.roadworthy" in match.lower():
                        out.append(("N", cwd, match))


def _close_script(texts, cwd, out):
    """`close.sh --human <item> approved|rejected ...`: the answer of a person. Listing the open
    items (`--human` alone) and asking for one (`--needs-human`) are the agent's to do."""
    if "--human" in texts:
        rest = texts[texts.index("--human") + 1:]
        if len(rest) >= 2 or any(t in ("approved", "rejected") for t in rest):
            out.append(("H", cwd, "human"))


def _scope_write(args, cwd, env, out, here):
    """The rite's own script that opens a front: S, with the repository the front opens in as the
    directory and the plan as an absolute path. A plan or a root only known at run time is `?`,
    which the gate cannot look an approval up for. `--owner` is the owner saying the front is his
    to open with no approval on record: a person's act, like the answer to a human verification."""
    if any(a.text == "--owner" for a in args):
        out.append(("H", cwd, "owner"))
    ops = _plain(args, ("--root", "--base"))
    root = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text == "--root"]
    where = cwd
    if root:
        where = "?" if root[0].dynamic else here(_path(root[0], env))
    if ops:
        out.append(("S", where, "?" if ops[0].dynamic else here(_path(ops[0], env))))


def _py_reaches_rite(code):
    """Whether Python code writes, removes or renames through a path that names `.roadworthy`.
    None when the code does not parse."""
    import ast
    try:
        tree = ast.parse(code)
    except Exception:
        return None
    tainted = set()

    def text_of(node):
        """The string a node certainly evaluates to, as far as constants go; None otherwise."""
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.BinOp) and isinstance(node.op, (ast.Add, ast.Mod)):
            left, right = text_of(node.left), text_of(node.right)
            if left is not None and right is not None:
                return left + right
        if isinstance(node, ast.JoinedStr):
            parts = [text_of(v.value) if isinstance(v, ast.FormattedValue) else text_of(v) for v in node.values]
            return "".join(x if x is not None else "\0" for x in parts)
        return None

    def is_path(text):
        # A PATH into the directory, not a sentence about it: the text a script is replacing in
        # the plugin's own source mentions `.roadworthy` all the time, with spaces around it.
        return text is not None and ".roadworthy" in text.lower() and not re.search(r"\s", text)

    def names_rite(node):
        if node is None:
            return False
        if is_path(text_of(node)):
            return True
        for sub in ast.walk(node):
            if isinstance(sub, ast.Name) and sub.id in tainted:
                return True
            if is_path(text_of(sub)):
                return True
        return False

    # Two passes over the assignments, so a name defined from another tainted name is caught
    # whatever the order the reader meets them in.
    for _ in range(3):
        for node in ast.walk(tree):
            targets_, value = [], None
            if isinstance(node, ast.Assign):
                targets_, value = node.targets, node.value
            elif isinstance(node, (ast.AnnAssign, ast.AugAssign)):
                targets_, value = [node.target], node.value
            elif isinstance(node, (ast.For, ast.comprehension)):
                targets_, value = [node.target], node.iter
            elif isinstance(node, ast.withitem) and node.optional_vars is not None:
                targets_, value = [node.optional_vars], node.context_expr
            elif isinstance(node, ast.NamedExpr):
                targets_, value = [node.target], node.value
            if value is not None and names_rite(value):
                for t in targets_:
                    for n in ast.walk(t):
                        if isinstance(n, ast.Name):
                            tainted.add(n.id)

    MODULES = ("os", "shutil", "subprocess", "pathlib", "io", "builtins", "tempfile", "glob", "sys")
    WRITERS = {"remove", "unlink", "rmdir", "removedirs", "rmtree", "rename", "renames", "replace", "truncate",
               "chmod", "chown", "copy", "copy2", "copyfile", "copytree", "move", "symlink", "link", "mkdir",
               "makedirs", "touch", "write_text", "write_bytes", "system", "popen", "run", "call", "check_call",
               "check_output", "Popen", "utime", "mkfifo", "writelines", "write", "dump", "open"}
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        f = node.func
        fname = f.id if isinstance(f, ast.Name) else (f.attr if isinstance(f, ast.Attribute) else "")
        receiver = f.value if isinstance(f, ast.Attribute) else None
        if fname == "open":
            # open(path) and open(path, "r") read. Anything else -- a mode with w, a, x or +, or a
            # mode this cannot fold -- is a write when the path names the rite.
            path = receiver if receiver is not None and not isinstance(receiver, ast.Name) else (node.args[0] if node.args else None)
            if isinstance(receiver, ast.Name) and receiver.id in tainted:
                path = receiver
            if receiver is not None and isinstance(receiver, ast.Name) and receiver.id in ("os", "io", "codecs", "builtins"):
                path = node.args[0] if node.args else None
            mode = node.args[1] if len(node.args) > 1 else next((k.value for k in node.keywords if k.arg == "mode"), None)
            if receiver is not None and path is receiver:
                mode = node.args[0] if node.args else mode
            m = text_of(mode) if mode is not None else "r"
            if names_rite(path) and (m is None or any(ch in m for ch in "wax+")):
                return True
            continue
        if fname in WRITERS and fname not in ("write", "writelines", "dump"):
            in_args = any(names_rite(a) for a in node.args) or any(names_rite(k.value) for k in node.keywords)
            module = receiver is None or (isinstance(receiver, ast.Name) and receiver.id in MODULES) \
                or (isinstance(receiver, ast.Attribute) and isinstance(receiver.value, ast.Name) and receiver.value.id in MODULES)
            if module:
                # os.remove(path), shutil.rmtree(path), a bare remove(path): the path is among the
                # arguments. A copy writes its DESTINATION only: `shutil.copy(rite_file, "/tmp/x")`
                # reads the rite.
                if fname in ("copy", "copy2", "copyfile", "copytree") and len(node.args) >= 2:
                    if names_rite(node.args[1]):
                        return True
                elif fname in ("run", "call", "check_call", "check_output", "Popen", "system", "popen"):
                    pass                        # judged below, as a command line
                elif in_args:
                    return True
                # A command line handed to a shell names the directory inside a sentence of its own.
                if fname in ("system", "popen", "run", "call", "check_call", "check_output", "Popen") and node.args:
                    first = node.args[0]
                    if isinstance(first, (ast.List, ast.Tuple)):
                        parts = [text_of(e) for e in first.elts]
                        line = " ".join(shlex.quote(x) for x in parts) if all(x is not None for x in parts) else None
                    else:
                        line = text_of(first)
                    # `subprocess.run(["cat", ".roadworthy/scope"])` reads; `["rm", ...]` does not.
                    if line is not None and ".roadworthy" in line.lower() and targets(line, "/", {}, 1):
                        return True
                    if line is None and any(t is not None and ".roadworthy" in t.lower()
                                            for sub in ast.walk(first) for t in [text_of(sub)]):
                        return True
            else:
                # A method: path.unlink(), path.write_text(...). The path is the object it is called
                # on. `text.replace(a, b)` with the directory named in its ARGUMENTS is string work;
                # the one-argument forms that take a destination path are the exception.
                if names_rite(receiver) and not (fname == "replace" and len(node.args) != 1):
                    return True
                if in_args and len(node.args) == 1 and fname in ("rename", "replace", "symlink", "link", "move", "copy"):
                    return True
    return False


def _interpreter(name, args, body, fed, cwd, out):
    """Inline code handed to an interpreter: N on the rite's directory when it writes there."""
    flags = INTERPRETERS.get(name, "c")
    codes, operands, i = [], [], 0
    while i < len(args):
        t = args[i].text
        if not args[i].dynamic and t.startswith("-") and len(t) > 1 and not t.startswith("--"):
            if any(ch in flags for ch in t[1:]) and i + 1 < len(args):
                codes.append(args[i + 1])
                i += 2
                continue
        elif t in ("--eval", "--print") and i + 1 < len(args):
            codes.append(args[i + 1])
            i += 2
            continue
        elif not t.startswith("-") or args[i].dynamic:
            operands.append(args[i])
        i += 1
    if not flags and operands:                      # awk: the program is the first operand
        codes.append(operands[0])
    texts = [c.text for c in codes if not c.dynamic]
    reads_stdin = not codes and (not operands or operands[0].text == "-")
    if reads_stdin:
        texts += [t for t in (body, fed) if t]
    for code in texts:
        code = code.lower() if ".roadworthy" in code.lower() and ".roadworthy" not in code else code
        if ".roadworthy" not in code and ".road" not in code:
            continue
        if name.startswith("python"):
            verdict = _py_reaches_rite(code)
            if verdict or (verdict is None and ".roadworthy" in code):
                out.append(("N", cwd, ".roadworthy/.interpreter"))
        elif ".roadworthy" in code and WRITES_TEXT.search(code):
            out.append(("N", cwd, ".roadworthy/.interpreter"))


def _tar(args, texts, cwd, env, out, here, emit):
    first = texts[0] if texts else ""
    letters = first.lstrip("-") if first and not first.startswith("--") else ""
    letters += "".join(t[1:] for t in texts[1:] if t.startswith("-") and not t.startswith("--"))
    d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text in ("-C", "--directory")]
    where = here(_path(d[0], env)) if d and not d[0].dynamic else cwd
    archive = None
    for i, a in enumerate(args):                    # the word after the cluster that ends in `f`
        t = a.text
        if t.startswith("--file="):
            archive = Word(t.split("=", 1)[1])
            break
        clustered = not t.startswith("--") and (t.startswith("-") or i == 0) and t.lstrip("-").endswith("f")
        if (t == "--file" or clustered) and i + 1 < len(args):
            archive = args[i + 1]
            break
    extract = "x" in letters or "--extract" in texts or "--get" in texts
    create = any(ch in letters for ch in "cru") or "--create" in texts or "--append" in texts
    if extract and "O" not in letters and "--to-stdout" not in texts:
        out.append(("U", cwd, where))
    elif create and archive is not None and archive.text != "-":
        emit("W", archive)


def _perl_in_place(t):
    """`-i`, `-pi`, `-i.bak`, `-0pi`: perl editing its operands in place. A switch that takes a
    value ends the cluster: the `i` of `-MFile::Basename` or of `-Ilib` is not `-i`."""
    if t.startswith("--") or not t.startswith("-"):
        return False
    for ch in t[1:]:
        if ch == "i":
            return True
        if ch in "MmIeEFxCD" or not (ch.isalpha() or ch.isdigit()):
            return False
    return False


def _perl_files(args):
    """perl's operands after its script: with `-e` or `-E` every operand is a file."""
    scripted, out, skip = False, [], False
    for a in args:
        t = a.text
        if skip:
            skip = False
            continue
        if t.startswith("-") and not t.startswith("--") and len(t) > 1 and not a.dynamic:
            for j, ch in enumerate(t[1:], 1):
                if ch in "eE":
                    scripted = True
                    skip = j == len(t) - 1          # `-e SCRIPT`: the next word is the script
                    break
                if ch in "MmIFxCD":
                    break
            continue
        out.append(a)
    return out if scripted else out[1:]


def _sed_flag(t):
    """What one sed argument says: ("inplace" | "script" | "", whether it takes the next word)."""
    if t == "--in-place" or t.startswith("--in-place="):
        return "inplace", False
    if t in ("--expression", "--file"):
        return "script", True
    if t.startswith(("--expression=", "--file=")):
        return "script", False
    if t.startswith("--") or not t.startswith("-") or len(t) < 2:
        return "", False
    for j, ch in enumerate(t[1:], 1):
        if ch in "iI":                              # -i (GNU, BSD) and -I (BSD): the rest is a suffix
            return "inplace", False
        if ch in "ef":                              # -e SCRIPT, -eSCRIPT: the rest is its value
            return "script", j == len(t) - 1
        if not ch.isalpha():
            break
    return "", False


def _sed_in_place(texts):
    return any(_sed_flag(t)[0] == "inplace" for t in texts)


def _sed_files(args):
    """sed's file operands: everything after the script, which is the first operand unless a
    `-e` or `-f` gave it."""
    scripted, out, skip = False, [], False
    for a in args:
        t = a.text
        if skip:
            skip = False
            continue
        if t.startswith("-") and len(t) > 1 and not a.dynamic:
            kind, takes = _sed_flag(t)
            if kind == "script":
                scripted, skip = True, takes
            continue
        if t or a.dynamic:
            out.append(a)
    return out if scripted else out[1:]


def _find_reach(args, texts):
    """(the roots find searches, whether what it selects could be the rite's own files). With no
    `-name` it selects everything."""
    roots = []
    for a in args:
        if a.text.startswith(("-", "(", "!")) and not a.dynamic:
            break
        roots.append(a)
    patterns = [texts[i + 1] for i, t in enumerate(texts[:-1]) if t in ("-name", "-iname", "-path", "-ipath", "-wholename")]
    reaches = not patterns or any(fnmatch.fnmatch(n, pat) or fnmatch.fnmatch("./.roadworthy/" + n, pat)
                                  for pat in patterns for n in RITE_NAMES)
    # `-not -path './.roadworthy/*'` (or `! -path`, or a `-prune` on it) leaves the rite's
    # directory out, which is exactly what the refusal of a sweep asks for.
    for i, t in enumerate(texts[:-2]):
        if t in ("-not", "!") and texts[i + 1] in ("-path", "-ipath", "-wholename") and ".roadworthy" in texts[i + 2].lower():
            reaches = False
    return roots, reaches


def _find(args, texts, cwd, env, out, here):
    roots, reaches = _find_reach(args, texts)
    removes = "-delete" in texts
    writes = False
    for i, t in enumerate(texts):
        if t in ("-exec", "-execdir", "-ok", "-okdir") and i + 1 < len(texts):
            verb, tail = os.path.basename(texts[i + 1]), texts[i + 2:]
            end = next((j for j, x in enumerate(tail) if x in (";", "+")), len(tail))
            inner = tail[:end]
            if verb in SHELLS:
                # A shell handed each file: what it does to them is in its script, read like any
                # other. `sh -c 'cat "$1"' _ {}` reads; with no script to read, it can do anything.
                script = next((x for j, x in enumerate(inner[1:], 1) if re.fullmatch(r"-[A-Za-z]*c", inner[j - 1])), None)
                did = {k for k, _, _ in targets(script, cwd, env, 1)} if script is not None else {"W", "R"}
                removes = removes or bool(did & {"R", "D", "F", "G", "X"})
                writes = writes or bool(did & {"W", "U", "N", "X"})
            if verb in ("rm", "unlink", "rmdir", "mv", "shred"):
                removes = True
            if verb in ("mv", "cp", "tee", "truncate", "touch", "install"):
                writes = True
            if (verb == "sed" and _sed_in_place(inner)) or (verb == "perl" and any(_perl_in_place(x) for x in inner)):
                writes = True
    if not (removes or writes):
        return
    for r in (roots or [Word(".")]):
        where = cwd if r.dynamic else here(_path(r, env))
        if removes:
            out.append(("F" if reaches else "D", cwd, where))
        if writes:
            out.append(("U", cwd, where))


def _git(args, cwd, env, out, here):
    i = 0
    while i < len(args):                            # git's own options, before the subcommand
        t = args[i].text
        if t == "-C" and i + 1 < len(args):
            if not args[i + 1].dynamic:
                cwd = here(_path(args[i + 1], env))
            i += 2
        elif t in ("-c", "--git-dir", "--work-tree", "--namespace") and i + 1 < len(args):
            i += 2
        elif t.startswith("-"):
            i += 1
        else:
            break
    if i >= len(args):
        return
    sub, rest = args[i].text, args[i + 1:]
    texts = [a.text for a in rest]
    dry = any(t == "--dry-run" or re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", t) for t in texts)

    def put(kind, word):
        if word.dynamic or not word.text:
            out.append(("D" if kind == "R" else "U", cwd, cwd))
            out.append(("B", cwd, ""))
            return
        matches = sorted(globlib.glob(os.path.join(cwd, word.text))) if word.bare and any(ch in word.text for ch in GLOB_CHARS) else []
        for match in matches:
            out.append((kind, cwd, match))
        if not matches:
            out.append((kind, cwd, _path(word, env)))

    if sub == "commit" and not dry:
        # What a commit takes is git's to say (hooks/guard-commit asks the index); the reader
        # says which repository, and what the command adds to the index by itself.
        long_valued = ("--message", "--file", "--reuse-message", "--reedit-message", "--author", "--date",
                       "--template", "--fixup", "--squash", "--cleanup", "--trailer", "--pathspec-from-file")
        named, letters, k, literal = [], "", 0, False
        while k < len(rest):
            t = rest[k].text
            if literal or rest[k].dynamic or not t.startswith("-") or t == "-":
                named.append(rest[k])
            elif t == "--":
                literal = True
            elif t.startswith("--"):
                k += 1 if t in long_valued else 0
            else:                                   # a cluster: `-am msg` -- m, F, C, c and t take a value
                for j, ch in enumerate(t[1:], 1):
                    if ch in "mFCct":
                        k += 1 if j == len(t) - 1 else 0
                        break
                    letters += ch
            k += 1
        out.append(("C", cwd, "-a" if ("a" in letters or "--all" in texts) else "-"))
        for a in named:
            out.append(("C", cwd, "?" if a.dynamic else _path(a, env)))
        return
    if sub == "add" and not dry:
        named = _plain(rest)
        everything = any(t in ("-A", "--all", "-u", "--update", ".") for t in texts) or not named
        if everything:
            out.append(("A", cwd, "*"))
        for a in named:
            out.append(("A", cwd, "*" if a.dynamic else _path(a, env)))
        return
    if sub == "rm":
        if "--cached" not in texts and not dry:
            for a in _plain(rest):
                put("R", a)
    elif sub == "mv":
        ops = _plain(rest)
        if len(ops) >= 2 and not dry:
            for a in ops[:-1]:
                put("R", a)
            put("W", ops[-1])
    elif sub == "checkout":
        if "--" in texts:                           # `git checkout [<tree>] -- <paths>` rewrites them
            # With no tree, or with HEAD, the paths go back to what git has: V, which removes a
            # difference. From any other tree it is a write of other content.
            tree = [t for t in _plain(rest[:texts.index("--")], ("-b", "-B")) if t.text != "HEAD"]
            for a in rest[texts.index("--") + 1:]:
                put("W" if tree else "V", a)
        else:                                       # without `--` a word may be a branch or a path;
            for a in _plain(rest, ("-b", "-B")):    # one that names the rite's directory is a path
                if _names_rite(a.text, here):
                    put("W", a)
    elif sub == "restore":
        if not (("--staged" in texts or "-S" in texts) and "--worktree" not in texts and "-W" not in texts):
            sourced = any(t in ("-s", "--source") or t.startswith("--source=") for t in texts)
            for a in _plain(rest, ("-s", "--source")):
                put("W" if sourced else "V", a)
    elif sub == "apply":
        if not any(t in ("--check", "--stat", "--numstat", "--summary", "--cached") for t in texts):
            out.append(("U", cwd, cwd))
    elif sub == "clean":
        forced = any(re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", t) or t == "--force" for t in texts)
        if forced and not dry:
            named = rest[texts.index("--") + 1:] if "--" in texts else _plain(rest, ("-e", "--exclude"))
            for a in named:
                put("R", a)
            if not named:
                # Everything untracked; with -x or -X what is ignored too, which is where a project
                # that ignores the rite's files keeps its scope, its snapshot and its ledgers.
                ignored = any(re.fullmatch(r"-[A-Za-z]*[xX][A-Za-z]*", t) for t in texts)
                spared = any(t in ("-e", "--exclude") and i + 1 < len(texts) and ".roadworthy" in texts[i + 1].lower()
                             for i, t in enumerate(texts)) or any(t.startswith("--exclude=") and ".roadworthy" in t.lower() for t in texts)
                # `-e .roadworthy` leaves the rite's directory out: an ordinary removal of what is
                # not tracked.
                out.append(("D" if spared else ("F" if ignored else "G"), cwd, cwd))
    elif sub == "stash":
        first = next((t for t in texts if not t.startswith("-")), "push")
        named = rest[texts.index("--") + 1:] if "--" in texts else []
        if first in ("push", "save") and named:
            for a in named:                         # only what it names leaves; the rite's, if named
                if _names_rite(a.text, here) or a.dynamic:
                    put("R", a)
        elif first in ("push", "save"):
            if any(t in ("-a", "--all") or re.fullmatch(r"-[A-Za-z]*a[A-Za-z]*", t) for t in texts):
                out.append(("F", cwd, cwd))         # tracked, untracked and ignored: all of it leaves
            elif any(t == "--include-untracked" or re.fullmatch(r"-[A-Za-z]*u[A-Za-z]*", t) for t in texts):
                out.append(("G", cwd, cwd))


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    cmd = os.environ.get("RW_CMD", "")
    seen = set()
    for item in targets(cmd, cwd):
        if item not in seen:
            seen.add(item)
            print("\t".join(item))


if __name__ == "__main__":
    main()
