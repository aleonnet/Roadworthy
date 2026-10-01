#!/usr/bin/env bash
# shellread
# Run alone: bash tests/scripts/shellread.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── hooks/shellread.py: one table, three questions ──────────────────────────
# The reader of shell commands lived inside hooks/rite-gate as forty lines that split on spaces.
# Both of its failures were measured on 2026-09-30: it took a READ for a write (a `>=` inside a
# heredoc, a `>` after an escaped quote), and it missed a write that hid behind a newline, an
# assignment, a wrapper, a substitution or a reserved word -- six of eight such forms aimed at the
# foundation went through. Each row below is a command and exactly what it must yield; the table is
# the grammar's contract, the way tests/scripts/globmatch.sh is for the globs.
section "shellread (reads are not writes, writes do not hide, targets are the real ones)"
python3 - "$ROOT/hooks" <<'PY' || FAIL=$((FAIL + 1))
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from shellread import targets

ENV = {"HOME": "/h", "TMPDIR": "/t", "PWD": "/repo", "JOB": "/job"}
Q, NL = chr(39), chr(10)
SNAP = ".roadworthy/plan.snapshot"

# (why it fails, command, expected set of "KIND dir path")
READS = "a read was taken for a write"
HIDES = "a write hid behind"
EXACT = "the reader named the wrong target"
TABLE = [
    # ── reads ──
    (READS, "python3 - <<'PY'" + NL + "if o.get('ts','') >= '2026-09-30T17': print(o)" + NL + "PY", []),
    (READS, 'grep -n "a\\|' + Q + '>' + Q + '\\|\\">\\"\\|>>x" hooks/rite-gate', []),
    (READS, "grep -n '>' src/a.py", []),
    (READS, "echo $(date) is fine", []),
    (READS, "[[ a > b ]] && echo yes", []),
    (READS, "(( a > b )) && echo yes", []),
    (READS, "echo $(( 3 > 2 ))", []),
    (READS, "# rm " + SNAP, []),
    (READS, "echo a # > note.txt", []),
    (READS, "cat <<'EOF'" + NL + "rm " + SNAP + NL + "echo x > f" + NL + "EOF", []),
    (READS, "sed -n 1,5p f.txt", []),
    (READS, "sed -e s/i/j/ f.txt", []),
    (READS, "find x -name r.sh | head -1 | xargs sed -n 1,60p", []),
    (READS, "git restore --staged a.py", []),
    (READS, "git rm --cached a.py", []),
    (READS, "git apply --check p.diff", []),
    (READS, "git clean -n", []),
    (READS, "tar tzf a.tgz", []),
    (READS, "diff <(sort a) <(sort b)", []),
    (READS, "command -v rm", []),
    (READS, 'eval "$(tool init -)"', []),
    (READS, "echo a 2>&1", []),
    # ── writes that used to hide ──
    (HIDES, "true" + NL + "rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "X=1 rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "command rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "echo $(rm " + SNAP + ")", ["R /repo " + SNAP]),
    (HIDES, "echo `rm " + SNAP + "`", ["R /repo " + SNAP]),
    (HIDES, 'echo "a $(rm ' + SNAP + ') b"', ["R /repo " + SNAP]),
    (HIDES, "if true; then rm " + SNAP + "; fi", ["R /repo " + SNAP]),
    (HIDES, "while true; do rm " + SNAP + "; done", ["R /repo " + SNAP]),
    (HIDES, "{ rm " + SNAP + "; }", ["R /repo " + SNAP]),
    (HIDES, "( rm " + SNAP + " )", ["R /repo " + SNAP]),
    (HIDES, "! rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "sudo -u me rm -rf " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "env -i FOO=1 rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "nohup rm " + SNAP + " &", ["R /repo " + SNAP]),
    (HIDES, "nice -n 5 sed -i s/a/b/ .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "sed -i.bak s/a/b/ .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "sed --in-place=.bak s/a/b/ .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "sed -ni s/a/b/p .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "perl -pi -e s/a/b/ .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, 'bash -c "rm ' + SNAP + '"', ["R /repo " + SNAP]),
    (HIDES, "eval rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "bash <<EOF" + NL + "rm " + SNAP + NL + "EOF", ["R /repo " + SNAP]),
    (HIDES, "cat <<EOF" + NL + "$(rm " + SNAP + ")" + NL + "EOF", ["R /repo " + SNAP]),
    (HIDES, "tee >(cat > .roadworthy/state)", ["W /repo .roadworthy/state"]),
    (HIDES, "echo x &> .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "echo x >| .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "touch .roadworthy/scope", ["W /repo .roadworthy/scope"]),
    (HIDES, "ln -s /etc/hosts .roadworthy/scope", ["W /repo .roadworthy/scope"]),
    (HIDES, "curl -s -o .roadworthy/state http://x", ["W /repo .roadworthy/state"]),
    (HIDES, "git checkout HEAD~1 -- .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "git mv a.py b.py", ["R /repo a.py", "W /repo b.py"]),
    (HIDES, "find .roadworthy -name plan.snapshot -delete", ["D /repo /repo/.roadworthy"]),
    (HIDES, "find . -name '*.bak' -exec rm {} +", ["D /repo /repo"]),
    (HIDES, "echo a | xargs rm", ["D /repo /repo"]),
    (HIDES, "git clean -fd", ["D /repo /repo"]),
    (HIDES, "git apply p.diff", ["U /repo /repo"]),
    (HIDES, "patch -p1 < p.diff", ["U /repo /repo"]),
    (HIDES, "tar xzf a.tgz -C sub", ["U /repo /repo/sub"]),
    # ── the target is the real one ──
    (EXACT, "cp /dev/null .roadworthy/state && true", ["W /repo .roadworthy/state"]),
    (EXACT, "sed -i '' s/a/b/ f.md && grep x y | wc -l", ["W /repo f.md"]),
    (EXACT, "rm a.txt && echo done", ["R /repo a.txt"]),
    (EXACT, "mv a.txt b.txt; echo ok", ["R /repo a.txt", "W /repo b.txt"]),
    (EXACT, "echo x > out.txt 2>/dev/null", ["W /repo out.txt", "W /repo /dev/null"]),
    (EXACT, "cat > notes.md <<'EOF'" + NL + "a > b" + NL + "EOF", ["W /repo notes.md"]),
    (EXACT, "cd /elsewhere && echo x > rel.txt", ["W /elsewhere rel.txt"]),
    (EXACT, "(cd /elsewhere && true); echo x > rel.txt", ["W /repo rel.txt"]),
    (EXACT, "git -C /other rm x.txt", ["R /other x.txt"]),
    (EXACT, 't=~/notes; cat a > "$t.bak"', ["W /repo /h/notes.bak"]),
    (EXACT, 'S=/tmp/s; echo x > $S/a.txt', ["W /repo /tmp/s/a.txt"]),
    (EXACT, 'echo x > "$JOB/out.txt"', ["W /repo /job/out.txt"]),
    (EXACT, 'out="$(mktemp)"; echo x > "$out"', ["W /repo /t/mktemp.unknown"]),
    (EXACT, 'cd "${TMPDIR:-/tmp}" && curl -s http://x -o n.py', ["W /t n.py"]),
    (EXACT, 'echo x > "$UNKNOWN/f"', ["U /repo /repo"]),
    (EXACT, 'for v in a b; do echo x > /tmp/run/$v/out; done', ["U /repo /tmp/run"]),
    (EXACT, 'for g in a b; do rm "goldens/$g.png"; done', ["D /repo goldens"]),
    (EXACT, "dd if=/dev/zero of=.roadworthy/scope", ["W /repo .roadworthy/scope"]),
    (EXACT, "tee -a a.log b.log", ["W /repo a.log", "W /repo b.log"]),
    (EXACT, "truncate -s 0 .roadworthy/scope", ["W /repo .roadworthy/scope"]),
    (EXACT, "install -m 644 /dev/null .roadworthy/scope", ["W /repo .roadworthy/scope"]),
    (EXACT, "bash skills/plan/scripts/scope-write.sh docs/plans/p.md --base abc", ["S /repo docs/plans/p.md"]),
    (EXACT, "skills/plan/scripts/scope-write.sh --root /r docs/plans/p.md", ["S /repo docs/plans/p.md"]),
]
bad = {}
for why, cmd, want in TABLE:
    got = sorted({"%s %s %s" % t for t in targets(cmd, "/repo", dict(ENV))})
    if got != sorted(want):
        bad.setdefault(why, []).append("%r\n          wanted %s\n          got    %s" % (cmd, sorted(want), got))
for why in (READS, HIDES, EXACT):
    n = sum(1 for w, _, _ in TABLE if w == why)
    if why in bad:
        print("  [FAIL] %s: %d of %d rows" % (why, len(bad[why]), n), file=sys.stderr)
        for line in bad[why]:
            print("        " + line, file=sys.stderr)
    else:
        print("  [OK]   %d rows: %s never happens" % (n, why))
sys.exit(1 if bad else 0)
PY

# The command line entry point is what the hooks call: one target per line, tab separated, and a
# command it cannot read is a write it could not rule out, never a crash.
OUT_CLI="$(RW_CMD='rm a.txt; echo x > b.txt' python3 "$ROOT/hooks/shellread.py" /repo)"
[ "$OUT_CLI" = "$(printf 'R\t/repo\ta.txt\nW\t/repo\tb.txt')" ] && ok "the entry point prints KIND, directory and path, tab separated" || fail "entry point output: $OUT_CLI"
[ -z "$(RW_CMD='grep -c x f.txt' python3 "$ROOT/hooks/shellread.py" /repo)" ] && ok "and nothing at all for a command that only reads" || fail "a read printed a target"

rw_end
