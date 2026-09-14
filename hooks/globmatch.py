#!/usr/bin/env python3
"""globmatch — the one glob grammar Roadworthy reads, in one place.

Three copies of this existed until 0.6.1: hooks/lib.sh (the fences), skills/close/scripts/close.sh
(the closing) and bin/rw-metrics (the evals). Only the first had the unanchored-name defect fixed in
0.6.0, and rw-metrics answered through fnmatch first, where `*` crosses a `/` -- so `app/*.py` meant
one thing to the scope lock and another to the instrument measuring it. tests/scripts/globmatch.sh
holds the three entry points to one table.

Grammar, anchored at the repository root, always:
  **/   any depth, including none        **   anything, separators included
  *     anything but a separator          ?    one character that is not a separator
A bare `README.md` matches at the root only; "at any depth" is spelled `**/README.md`.
Blank globs and `#` comments are skipped, so a scope file can be passed line by line.

Usage: globmatch.py <path> <glob>[,<glob>...]     exit 0 when any glob matches, 1 otherwise
Import: sys.path.insert(0, "<plugin>/hooks"); from globmatch import matches
"""
import os
import re
import sys


def to_regex(glob):
    glob = os.path.normpath(glob)
    out, i = "", 0
    while i < len(glob):
        if glob.startswith("**/", i):
            out += "(?:.*/)?"; i += 3
        elif glob.startswith("**", i):
            out += ".*"; i += 2
        elif glob[i] == "*":
            out += "[^/]*"; i += 1
        elif glob[i] == "?":
            out += "[^/]"; i += 1
        else:
            out += re.escape(glob[i]); i += 1
    return "^" + out + "$"


def matches(path, globs):
    """True when `path` (relative to the root) matches any glob in `globs`."""
    path = os.path.normpath(path)
    for glob in globs:
        glob = glob.strip()
        if not glob or glob.startswith("#"):
            continue
        if re.match(to_regex(glob), path):
            return True
    return False


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: globmatch.py <path> <glob>[,<glob>...]\n")
        sys.exit(2)
    sys.exit(0 if matches(sys.argv[1], sys.argv[2].split(",")) else 1)
