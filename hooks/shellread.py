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
every separator including the newline, subshells, reserved words, assignments, wrappers
(`command`, `env`, `sudo`, `xargs`...), `bash -c` and `eval` read from the inside, and the directory
in force (`cd`, `git -C`). The grammar lives here and nowhere else, like hooks/globmatch.py.

What it emits, one per line, as KIND <TAB> DIRECTORY <TAB> PATH:
  W  a write to PATH              R  a removal of PATH
  U  a write somewhere under PATH (the target is not on the command line: `patch`, `git apply`,
     an unresolved variable)      D  a removal somewhere under PATH (`find ... -delete`, `xargs rm`)
  S  skills/plan/scripts/scope-write.sh run on the plan PATH
PATH is as written; DIRECTORY is the directory in force for it.

THE LIMIT, DECLARED: an interpreter that opens the file itself (`python3 -c`, `node -e`, `awk`
with a redirection inside the program) writes through nothing this can name. Measured on 33,811
real commands on 2026-09-30, 25.7% use an interpreter or a heredoc: denying what cannot be read
would deny a quarter of all work. What backs it up is exact and lives elsewhere: the commit
(hooks/guard-commit reads git's own index) and the closing (the front's diff).

Usage: RW_CMD='<command>' shellread.py <cwd>
Import: sys.path.insert(0, "<plugin>/hooks"); from shellread import targets
"""
import os
import re
import sys

OPS = ("&&", "||", ";;", "|&", ";", "|", "&", "(", ")")
REDIR = re.compile(r"(\d*)(&>>|&>|>>|>\||>&|<<<|<<-|<<|<&|<>|>|<)")
WRITE_REDIRS = (">", ">>", ">|", "&>", "&>>")
NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
ASSIGN = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=")
SHELLS = ("bash", "sh", "zsh", "dash", "ksh")
# Words after which a command still starts: the reader goes on to the next word.
PREFIX_WORDS = ("if", "then", "else", "elif", "while", "until", "do", "!", "{", "time")
# Words that end or open a construct with no command of their own on that position.
NO_COMMAND = ("fi", "done", "esac", "}", "for", "case", "select", "function", "in", "((")


class Word:
    """One shell word after quote removal.

    A word is kept as PARTS -- literal text, a variable, something only known at run time -- and
    turned into text when the command it belongs to is reached, never when the line is split: a
    variable assigned earlier on the same line (`t=/tmp/x; echo > "$t"`) is known by then.
    `dynamic` means part of the word could not be resolved."""
    __slots__ = ("parts", "text", "dynamic", "subs", "tilde", "proc", "prefix")

    def __init__(self, text="", dynamic=False, subs=None, tilde=False, proc=False):
        self.parts = ([("l", text)] if text else []) + ([("d",)] if dynamic else [])
        self.text, self.dynamic, self.subs, self.tilde = text, dynamic, subs or [], tilde
        self.proc = proc                            # `<( )` or `>( )`: a pipe, never a file
        self.prefix = ""                            # the text before the first unresolved part

    def add(self, parts):
        for part in parts:
            if part[0] == "l" and self.parts and self.parts[-1][0] == "l":
                self.parts[-1] = ("l", self.parts[-1][1] + part[1])
            else:
                self.parts.append(part)

    def resolve(self, env):
        text, dynamic, prefix = "", False, None
        for part in self.parts:
            if part[0] == "l":
                text += part[1]
            elif part[0] == "v" and part[1] in env:
                text += env[part[1]]
            elif part[0] == "vd":
                text += env.get(part[1]) or part[2]
            else:
                if prefix is None:
                    prefix = text
                dynamic = True
        self.text, self.dynamic, self.prefix = text, dynamic, (prefix or "")
        return self


def _close(s, i, open_ch="(", close_ch=")"):
    """Index of the bracket that closes the one opened just before s[i], quotes respected."""
    depth, n = 1, len(s)
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
        if c == open_ch:
            depth += 1
        elif c == close_ch:
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return n


def _dq_end(s, i):
    """Index of the double quote that closes the one opened just before s[i]."""
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == "$" and s.startswith("$(", i) and not s.startswith("$((", i):
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


def _dollar(s, i):
    """An expansion starting at s[i] (`$` or a backtick): (parts, subs, next index)."""
    n = len(s)
    if s[i] == "`":
        j = _bt_end(s, i + 1)
        return [("d",)], [s[i + 1:j]], j + 1
    if s.startswith("$((", i):
        j = s.find("))", i + 3)
        return [("d",)], [], (n if j == -1 else j + 2)
    if s.startswith("$(", i):
        j = _close(s, i + 2)
        return [("d",)], [s[i + 2:j]], j + 1
    if s.startswith("${", i):
        j = _close(s, i + 2, "{", "}")
        inner = s[i + 2:j]
        if NAME.fullmatch(inner):
            return [("v", inner)], [], j + 1
        m = re.fullmatch(r"([A-Za-z_][A-Za-z0-9_]*):?[-=]([^$`\\\"']*)", inner)
        if m:                                       # ${NAME:-default}: the value, or the default
            return [("vd", m.group(1), m.group(2))], [], j + 1
        return [("d",)], [], j + 1
    if s.startswith("$'", i):                       # $'...' is a quoted string, not an expansion
        j = i + 2
        while j < n and s[j] != "'":
            j += 2 if s[j] == "\\" else 1
        return [("l", s[i + 2:j])], [], j + 1
    m = NAME.match(s, i + 1)
    if m:
        return [("v", m.group(0))], [], m.end()
    if i + 1 < n and (s[i + 1].isdigit() or s[i + 1] in "?!$#*@-"):
        return [("d",)], [], i + 2
    return [("l", "$")], [], i + 1


def _dq_parts(inner):
    """The parts of a double-quoted string: (parts, subs)."""
    parts, subs, i, n = [], [], 0, len(inner)
    while i < n:
        c = inner[i]
        if c == "\\" and i + 1 < n:
            if inner[i + 1] in '"\\$`':
                parts.append(("l", inner[i + 1]))
            elif inner[i + 1] != "\n":
                parts.append(("l", c + inner[i + 1]))
            i += 2
            continue
        if c in "$`":
            ps, sb, i = _dollar(inner, i)
            parts += ps
            subs += sb
            continue
        parts.append(("l", c))
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
                w.add([("l", s[i + 1])])
            i += 2
            continue
        if c == "'":
            j = s.find("'", i + 1)
            j = n if j == -1 else j
            w.add([("l", s[i + 1:j])])
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
            ps, sb, i = _dollar(s, i)
            w.add(ps)
            w.subs += sb
            continue
        if c in " \t\n;&|<>()":
            break
        w.add([("l", c)])
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
        if c in "<>" and s.startswith("(", i + 1):  # process substitution: its inside is a command
            j = _close(s, i + 2)
            toks.append(("W", Word(dynamic=True, subs=[s[i + 2:j]], proc=True)))
            i = j + 1
            continue
        if s.startswith("((", i):                   # (( arithmetic )): a `>` inside is not a redirection
            j = s.find("))", i + 2)
            toks.append(("W", Word("((")))
            i = n if j == -1 else j + 2
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


def _path(word, env):
    if word.tilde and (word.text == "~" or word.text.startswith("~/")):
        return env.get("HOME", "~") + word.text[1:]
    return word.text


def _known_dir(word, env, cwd):
    """The directory a word only partly known is certainly under: `/tmp/run/$i/out` is under
    /tmp/run, `lib/$f` is under lib, `$x` is under nothing but the directory in force."""
    prefix = word.prefix
    if word.tilde and (prefix == "~" or prefix.startswith("~/")):
        prefix = env.get("HOME", "~") + prefix[1:]
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


def targets(cmd, cwd, env=None, depth=0):
    """Every write and removal a command names: a list of (kind, directory, path)."""
    out = []
    if depth > 8:
        return out
    env = dict(env) if env is not None else _base_env(cwd)
    state = {"cwd": cwd}
    cur, stack = [], []
    for tok in tokenize(cmd) + [("O", "\n")]:
        if tok[0] != "O":
            cur.append(tok)
            continue
        _simple(cur, state, env, out, depth)
        cur = []
        if tok[1] == "(":                           # a subshell keeps its `cd` to itself
            stack.append(state["cwd"])
        elif tok[1] == ")" and stack:
            state["cwd"] = stack.pop()
    return out


def _simple(cur, state, env, out, depth):
    # Words become text HERE, with what is known when this command is reached.
    words = [t[1].resolve(env) for t in cur if t[0] == "W"]
    redirs = [t for t in cur if t[0] == "R"]
    for r in redirs:
        if r[3] is not None and r[1] not in ("<<", "<<-"):
            r[3].resolve(env)
    cwd = state["cwd"]
    here = lambda p: p if os.path.isabs(p) else os.path.normpath(os.path.join(cwd, p))

    def emit(kind, word):
        """W or R on a word; a word only known at run time becomes U or D on the directory."""
        if isinstance(word, Word):
            if word.proc:
                return
            if word.dynamic or not word.text:
                out.append(("U" if kind == "W" else "D", cwd, _known_dir(word, env, cwd)))
                return
            word = _path(word, env)
        if word:
            out.append((kind, cwd, word))

    # Substitutions run first, in a subshell of their own.
    for w in words + [r[3] for r in redirs if r[3] is not None]:
        for sub in w.subs:
            out.extend(targets(sub, cwd, env, depth + 1))

    k = 0
    while k < len(words):
        t = words[k].text
        m = ASSIGN.match(t)
        if m and not words[k].tilde:
            w = words[k]
            if not w.dynamic:
                value = t[m.end():]
                if value == "~" or value.startswith("~/"):      # the shell expands it after the `=`
                    value = env.get("HOME", "~") + value[1:]
                env[m.group(1)] = value
            elif len(w.subs) == 1 and re.match(r"\s*mktemp\b", w.subs[0]) and t[m.end():] == "":
                # `x="$(mktemp)"` is a path under the temporary directory, whatever its name.
                env[m.group(1)] = env.get("TMPDIR", "/tmp").rstrip("/") + "/mktemp.unknown"
            else:
                env.pop(m.group(1), None)
            k += 1
        elif t in PREFIX_WORDS and not words[k].dynamic:
            k += 1
        else:
            break
    name = ""
    if k < len(words) and not words[k].dynamic and words[k].text not in NO_COMMAND:
        name = os.path.basename(words[k].text)
    args = words[k + 1:] if name else []
    via_xargs = False

    # Wrappers hand the rest of the line to another command.
    while name:
        if name in ("command", "builtin", "exec", "nohup"):
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
        else:
            break
        if not rest or rest[0].dynamic:
            name, args = "", []
            break
        name, args = os.path.basename(rest[0].text), rest[1:]

    in_test = name == "[["
    for _, op, _fd, target, body, quoted in redirs:
        if op in ("<<", "<<-") and body is not None and not quoted:
            # An unquoted heredoc is expanded before it is fed: `$( )` inside it runs.
            for sub in _dq_parts(body)[1]:
                out.extend(targets(sub, cwd, env, depth + 1))
        if in_test:
            break
        if op in WRITE_REDIRS or (op == ">&" and target is not None and not re.fullmatch(r"\d+|-", target.text or "x")):
            if target is not None:
                emit("W", target)
        elif op in ("<<", "<<-") and body is not None and name in SHELLS and not _plain(args, ("-c", "-o")):
            out.extend(targets(body, cwd, env, depth + 1))       # a shell reading a heredoc runs it
        elif op == "<<<" and target is not None and name in SHELLS and not target.dynamic:
            out.extend(targets(target.text, cwd, env, depth + 1))
    if not name:
        return

    texts = [a.text for a in args]
    if name in SHELLS:
        if "-c" in texts and texts.index("-c") + 1 < len(args):
            script = args[texts.index("-c") + 1]
            # A script only known at run time is not read: denying `bash -c "$x"` would deny every
            # `eval "$(tool init)"` on earth. Its substitutions were already read above.
            if not script.dynamic:
                out.extend(targets(script.text, cwd, env, depth + 1))
            return
        ops = _plain(args, ("-o", "-O"))
        if ops and os.path.basename(ops[0].text) == "scope-write.sh" and len(ops) > 1:
            out.append(("S", cwd, _path(ops[1], env)))
        return
    if name == "scope-write.sh":
        ops = _plain(args, ("--root", "--base"))
        if ops:
            out.append(("S", cwd, _path(ops[0], env)))
        return
    if name == "eval":
        if not any(a.dynamic for a in args):
            out.extend(targets(" ".join(texts), cwd, env, depth + 1))
        return
    if name in ("cd", "pushd"):
        ops = _plain(args)
        if ops and not ops[0].dynamic and ops[0].text != "-":
            state["cwd"] = here(_path(ops[0], env))
        elif not ops and name == "cd":
            state["cwd"] = env.get("HOME", cwd)
        return

    if via_xargs and name in ("rm", "unlink", "rmdir", "mv"):
        out.append(("D", cwd, cwd))                 # the names arrive on standard input
    if via_xargs and (name in ("cp", "mv", "tee", "touch", "install")
                      or (name == "sed" and any(_in_place(t) for t in texts))
                      or (name == "perl" and any(_perl_in_place(t) for t in texts))):
        out.append(("U", cwd, cwd))

    if name == "tee":
        for a in _plain(args):
            emit("W", a)
    elif name in ("cp", "install", "ln", "rsync"):
        dest = [a for i, a in enumerate(args[1:], 1) if args[i - 1].text in ("-t", "--target-directory")]
        dest += [Word(a.text.split("=", 1)[1]) for a in args if a.text.startswith("--target-directory=")]
        ops = _plain(args, ("-t", "--target-directory", "-m", "-o", "-g", "-S", "-e"))
        if dest:
            emit("W", dest[0])
        elif len(ops) >= 2:
            emit("W", ops[-1])
    elif name == "mv":
        ops = _plain(args, ("-t", "--target-directory", "-S"))
        if len(ops) >= 2:
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
        if any(_in_place(t) for t in texts):
            scripted = any(t in ("-e", "-f", "--expression", "--file") or t.startswith(("--expression=", "--file=")) for t in texts)
            ops = [a for a in _plain(args, ("-e", "-f", "--expression", "--file")) if a.text or a.dynamic]
            for a in (ops if scripted else ops[1:]):
                emit("W", a)
    elif name == "perl":
        if any(_perl_in_place(t) for t in texts):
            scripted = any(re.fullmatch(r"-[A-Za-z0]*e", t) for t in texts)
            ops = _plain(args, ("-e", "-E"))
            for a in (ops if scripted else ops[1:]):
                emit("W", a)
    elif name in ("rm", "unlink", "rmdir"):
        for a in _plain(args):
            emit("R", a)
    elif name == "curl":
        for i, a in enumerate(args):
            if a.text in ("-o", "--output") and i + 1 < len(args):
                emit("W", args[i + 1])
            elif a.text.startswith("--output="):
                emit("W", Word(a.text.split("=", 1)[1]))
            elif re.fullmatch(r"-[A-Za-z]*O[A-Za-z]*", a.text) or a.text == "--remote-name":
                out.append(("U", cwd, cwd))
    elif name == "wget":
        named = False
        for i, a in enumerate(args):
            if a.text in ("-O", "--output-document") and i + 1 < len(args):
                named = True
                if args[i + 1].text != "-":
                    emit("W", args[i + 1])
        if not named and "--spider" not in texts:
            out.append(("U", cwd, cwd))
    elif name == "patch":
        if "--dry-run" not in texts:
            d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text in ("-d", "--directory")]
            out.append(("U", cwd, here(_path(d[0], env)) if d and not d[0].dynamic else cwd))
    elif name in ("tar", "bsdtar"):
        mode = texts[0] if texts else ""
        if "--extract" in texts or "--get" in texts or (re.fullmatch(r"-?[A-Za-z]*x[A-Za-z]*", mode) and not mode.startswith("--")):
            d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text in ("-C", "--directory")]
            out.append(("U", cwd, here(_path(d[0], env)) if d and not d[0].dynamic else cwd))
    elif name == "unzip":
        if not any(t in ("-l", "-t", "-p", "-v", "-Z") for t in texts):
            d = [args[i + 1] for i, a in enumerate(args[:-1]) if a.text == "-d"]
            out.append(("U", cwd, here(_path(d[0], env)) if d and not d[0].dynamic else cwd))
    elif name == "find":
        roots = []
        for a in args:
            if a.text.startswith(("-", "(", "!")) and not a.dynamic:
                break
            roots.append(a)
        removes = "-delete" in texts
        writes = False
        for i, t in enumerate(texts):
            if t in ("-exec", "-execdir", "-ok", "-okdir") and i + 1 < len(texts):
                verb = os.path.basename(texts[i + 1])
                removes = removes or verb in ("rm", "unlink", "rmdir", "mv")
                writes = writes or verb in ("mv", "cp", "sed", "perl", "tee", "truncate", "touch", "install")
        for kind, on in (("D", removes), ("U", writes)):
            if on:
                for r in (roots or [Word(".")]):
                    out.append((kind, cwd, cwd if r.dynamic else here(_path(r, env))))
    elif name == "git":
        _git(args, cwd, env, out, emit, here)


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


def _perl_in_place(t):
    """`-i`, `-pi`, `-i.bak`, `-0pi`: perl editing its operands in place."""
    return not t.startswith("--") and re.fullmatch(r"-[A-Za-z0]*i.*", t) is not None


def _in_place(t):
    """Whether a sed argument asks for editing in place, in any of its spellings."""
    if t == "--in-place" or t.startswith("--in-place="):
        return True
    if t.startswith("--") or not t.startswith("-"):
        return False
    # `-i`, `-i.bak`, and `i` inside a cluster of flags (`-ni`, `-Ei`). After `-e` or `-f` in the
    # same cluster the rest is that option's value, never a flag.
    for ch in t[1:]:
        if ch == "i":
            return True
        if ch in "ef":
            return False
        if not ch.isalpha():
            return False
    return False


def _git(args, cwd, env, out, emit, here):
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

    def put(kind, word):
        if word.dynamic or not word.text:
            out.append(("U" if kind == "W" else "D", cwd, cwd))
        else:
            out.append((kind, cwd, _path(word, env)))

    if sub == "rm":
        if "--cached" not in texts:
            for a in _plain(rest):
                put("R", a)
    elif sub == "mv":
        ops = _plain(rest)
        if len(ops) >= 2:
            for a in ops[:-1]:
                put("R", a)
            put("W", ops[-1])
    elif sub == "checkout":
        if "--" in texts:                           # `git checkout [<tree>] -- <paths>` rewrites them
            for a in rest[texts.index("--") + 1:]:
                put("W", a)
    elif sub == "restore":
        if not (("--staged" in texts or "-S" in texts) and "--worktree" not in texts and "-W" not in texts):
            for a in _plain(rest, ("-s", "--source")):
                put("W", a)
    elif sub == "apply":
        if not any(t in ("--check", "--stat", "--numstat", "--summary", "--cached") for t in texts):
            out.append(("U", cwd, cwd))
    elif sub == "clean":
        forced = any(re.fullmatch(r"-[A-Za-z]*f[A-Za-z]*", t) or t == "--force" for t in texts)
        dry = any(re.fullmatch(r"-[A-Za-z]*n[A-Za-z]*", t) or t == "--dry-run" for t in texts)
        if forced and not dry:
            named = rest[texts.index("--") + 1:] if "--" in texts else []
            for a in named:
                put("R", a)
            if not named:
                out.append(("D", cwd, cwd))


def main():
    cwd = sys.argv[1] if len(sys.argv) > 1 else os.getcwd()
    cmd = os.environ.get("RW_CMD", "")
    try:
        found = targets(cmd, cwd)
    except Exception:
        # A command this could not read is a write it could not rule out, in the directory it ran.
        found = [("U", cwd, cwd)]
    seen = set()
    for item in found:
        if item not in seen:
            seen.add(item)
            print("\t".join(item))


if __name__ == "__main__":
    main()
