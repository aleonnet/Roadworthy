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
    # the reads the first cold review found being taken for writes (2026-09-30)
    (READS, "[[ $a < $b && $c > $d ]]", []),
    (READS, '[[ -f README.md && "x" > "a" ]] && echo yes', []),
    (READS, "[[ ( 2 > 1 ) ]] && echo y", []),
    (READS, "[[ $x == a* || $y > b ]]", []),
    (READS, '[[ "$x" =~ ^(a|b)>c$ ]]', []),
    (READS, "if [[ $v > 1.2 ]]; then echo n; fi", []),
    (READS, "cat README.md | while read x; do [[ $x > m ]] && echo $x; done", []),
    (READS, "echo $(( (1+(2))>0 ))", []),
    (READS, "(( (1+(2)) > 0 )) && echo y", []),
    (READS, "if (( $(echo $(echo 1)) > 0 )); then echo y; fi", []),
    (READS, 'echo "$(( $(echo $(echo 1)) > 0 ))"', []),
    (READS, "x=$(( y > 3 ? 1 : 0 ))", []),
    (READS, "for ((i=0;i<3;i++)); do echo $i; done", []),
    (READS, "echo $[2>1]", []),
    (READS, "echo ${x//>/-}", []),
    (READS, "msg=$(cat <<'E'" + NL + "1) a > b" + NL + "E" + NL + ")" + NL + 'echo "$msg"', []),
    (EXACT, 'git commit -m "$(cat <<' + Q + "E" + Q + NL + "fix: a > b (see 1) and it" + Q + "s ok" + NL + "E" + NL + ')"', ["C /repo -"]),
    (READS, "perl -MFile::Basename -e 'print basename($ARGV[0])' README.md", []),
    (READS, "perl -Ilib -ne 'print' README.md", []),
    (READS, "find . -name '*.md' -exec sed -n '1,3p' {} +", []),
    (READS, "find . -type f -exec perl -ne 'print if /x/' {} +", []),
    (READS, "wget -qO- http://x", []),
    (READS, "wget --output-document=- http://x", []),
    (READS, "curl -XPOST http://x", []),
    (READS, "curl -s -o - http://x", []),
    (READS, "echo err >&$fd", []),
    (READS, "unzip -Z1 a.zip", []),
    (READS, "unzip -lv a.zip", []),
    (READS, "tar -xOf a.tar README.md", []),
    (READS, "rsync -an src/ backup/", []),
    (READS, "git mv -n README.md R.md", []),
    (READS, "git rm -n README.md", []),
    (READS, "git stash list", []),
    (READS, "git checkout main", []),
    (READS, "test \"$a\" \\> \"$b\"", []),
    (READS, "echo 'it'\\''s > x'", []),
    # reading the rite's own files is reading
    (READS, "cat .roadworthy/state", []),
    (READS, "ls -la .roadworthy && cat " + SNAP + " | head", []),
    (READS, "wc -l < .roadworthy/refutations.jsonl", []),
    (READS, "tail -2 .roadworthy/refutations.jsonl | cut -c1-200", []),
    (READS, "diff .roadworthy/state .roadworthy/gates", []),
    (READS, "for f in .roadworthy/*; do wc -l \"$f\"; done", []),
    (EXACT, "git add .roadworthy/gates", ["A /repo .roadworthy/gates"]),
    (READS, "[ -f .roadworthy/scope ] && echo y", []),
    (READS, "grep -rn 'rm ' .roadworthy/gates", []),
    (READS, 'echo "rm ' + SNAP + '"', []),
    (READS, "cat <<'E' | grep rm" + NL + "rm " + SNAP + NL + "E", []),
    (READS, 'python3 -c "print(open(' + Q + '.roadworthy/state' + Q + ').read())"', []),
    (READS, 'python3 -c "import json; print(json.load(open(' + Q + '.roadworthy/plan.snapshot' + Q + '))[' + Q + 'base_head' + Q + '])"', []),
    # the plugin's own source is edited by a script that MENTIONS the directory in the text it
    # replaces: the string is content, never the path of a write
    (READS, "python3 - <<'PY'" + NL + 'p = "hooks/rite-gate"' + NL + "s = open(p).read()" + NL
            + 's = s.replace("old", "see .roadworthy/scope")' + NL + 'open(p, "w").write(s)' + NL + "PY", []),
    (READS, "node -e \"console.log(require('fs').readFileSync('.roadworthy/state','utf8'))\"", []),
    (READS, "awk -F: '{print $1}' .roadworthy/gates", []),
    # reads the dead-end hunt of 2026-10-01 found being refused
    (READS, "node -e \"require('fs').readFileSync('.roadworthy/scope','utf8').split('\\n').forEach(l => console.log(l))\"", []),
    (READS, 'python3 -c "import subprocess; print(subprocess.run([' + Q + 'cat' + Q + ', ' + Q + '.roadworthy/scope' + Q + '], capture_output=True).stdout)"', []),
    (READS, 'python3 -c "import shutil; shutil.copy(' + Q + '.roadworthy/gates' + Q + ', ' + Q + '/tmp/gates.copy' + Q + ')"', []),
    (READS, "ls .roadworthy | xargs -n1 basename", []),
    (READS, "find .roadworthy -type f | xargs -I{} sh -c 'echo {}; tail -1 {}'", []),
    (EXACT, "tar czf /tmp/rw.tgz .roadworthy", ["W /repo /tmp/rw.tgz"]),
    (EXACT, "grep -rl 'c = ' src | xargs -I{} cp {} {}.orig", ["U /repo /repo"]),
    (HIDES, 'python3 -c "import shutil; shutil.copy(' + Q + '/tmp/forged' + Q + ', ' + Q + '.roadworthy/scope' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "git clean -fdX -e .roadworthy", ["D /repo /repo"]),
    (HIDES, "find . -type d -empty -not -path './.roadworthy/*' -delete", ["D /repo /repo"]),
    (READS, "ls .roadworthy | xargs -n1 echo", []),
    (READS, 'cd "$(git rev-parse --show-toplevel)" && cat .roadworthy/state', []),
    (READS, "bash skills/close/scripts/close.sh --check", []),
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
    (EXACT, "git checkout -- outside/b.py", ["V /repo outside/b.py"]),
    (EXACT, "git checkout HEAD -- outside/b.py", ["V /repo outside/b.py"]),
    (EXACT, "git restore outside/b.py", ["V /repo outside/b.py"]),
    (EXACT, "git restore --source HEAD~3 outside/b.py", ["W /repo outside/b.py"]),
    (HIDES, "git mv a.py b.py", ["R /repo a.py", "W /repo b.py"]),
    (HIDES, "find .roadworthy -name plan.snapshot -delete", ["F /repo /repo/.roadworthy"]),
    (HIDES, "find . -name plan.snapshot -delete", ["F /repo /repo"]),
    (HIDES, "find . -delete", ["F /repo /repo"]),
    (HIDES, "find . -name '*.bak' -exec rm {} +", ["D /repo /repo"]),
    (HIDES, "find .roadworthy -name state -exec sh -c 'rm \"$1\"' _ {} \\;", ["F /repo /repo/.roadworthy"]),
    (HIDES, "find .roadworthy -name state -exec sh -c 'echo x > \"$1\"' _ {} \\;", ["U /repo /repo/.roadworthy"]),
    (HIDES, "find .roadworthy -name state -exec bash {} \\;", ["F /repo /repo/.roadworthy", "U /repo /repo/.roadworthy"]),
    (HIDES, "find . -name state | xargs rm", ["D /repo /repo", "F /repo /repo"]),
    (HIDES, "find . -name '*.bak' -print0 | xargs -0 rm", ["D /repo /repo"]),
    (HIDES, "echo a | xargs rm", ["D /repo /repo"]),
    (HIDES, "echo " + SNAP + " | xargs rm", ["D /repo /repo", "N /repo " + SNAP, "N /repo .roadworthy"]),
    # What git does not track: G when only the untracked leave, F when the ignored leave too.
    (HIDES, "git clean -fd", ["G /repo /repo"]),
    (HIDES, "git clean -fdx", ["F /repo /repo"]),
    (HIDES, "git clean -f -- build/x.o", ["R /repo build/x.o"]),
    (HIDES, "git stash -u", ["G /repo /repo"]),
    (HIDES, "git stash push -u -- .roadworthy/scope", ["R /repo .roadworthy/scope"]),
    (READS, "git stash push -u -m 'not this front' -- tools/x.mjs docs/__pycache__", []),
    (READS, "find .roadworthy -type f -exec sh -c 'echo \"--- {} ---\"; cat \"{}\"' \\;", []),
    # A word that MENTIONS the directory is not a path into it (12 of 55 real commands, 2026-09-30).
    (READS, "E=/p/overnight-entry.sh && \"$E\" --decision \"the guard denies while .roadworthy/overnight exists\"", []),
    (READS, "note.sh --blocker 'see .roadworthy/gates; nothing ran'", []),
    (READS, "fire rite-gate '{\"tool_input\":{\"file_path\":\"/x/.roadworthy/gates\"}}'", []),
    # A name only partly known is known by its end: a dated file under docs/plans is not the rite's.
    (EXACT, 'H="docs/plans/$(date +%H%M)-handoff.md"; cat > "$H" <<' + Q + "E" + Q + NL + "see .roadworthy/state" + NL + "E", ["U /repo docs/plans"]),
    (EXACT, 'S=/tmp/s; i=$((i+1)); (eval "$g") > $S/gate_$i.log 2>&1; cat .roadworthy/gates', ["U /repo /tmp/s"]),
    (EXACT, 'echo x > "$JOBDIR_UNSET/tmp/close.log"; cat .roadworthy/state', ["U /repo /repo"]),
    (HIDES, 'for r in a b; do cat >> $r/.roadworthy/scope; done', ["U /repo /repo", "N /repo .roadworthy"]),
    (HIDES, 'G="$(tool)/.roadworthy/gates"; cp x "$G"', ["U /repo /repo", "N /repo .roadworthy"]),
    # ...and by where it certainly is: a toy repository under a known directory is judged THERE.
    (EXACT, 'R="/scratch/toy-$$"; echo x > "$R/.roadworthy/scope"', ["U /repo /scratch", "N /repo /scratch/.roadworthy"]),
    (HIDES, 'while read f; do rm "$f"; done <<E' + NL + ".roadworthy/state" + NL + "E", ["D /repo /repo", "N /repo .roadworthy"]),
    (HIDES, "git stash push --all", ["F /repo /repo"]),
    (HIDES, "git checkout .roadworthy/gates", ["W /repo .roadworthy/gates"]),
    # ── what the first cold review of the reader walked through (2026-09-30) ──
    (HIDES, "[[ -n x ]] > .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "((echo a); rm " + SNAP + ")", ["R /repo " + SNAP]),
    (HIDES, "echo $((echo a); rm " + SNAP + ")", ["R /repo " + SNAP]),
    (HIDES, "mv -t /tmp " + SNAP, ["R /repo " + SNAP, "W /repo /tmp"]),
    (HIDES, "sed -i -es/passed/x/ .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "sed -I '' s/passed/x/ .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "sed -Ei '' s/passed/x/ .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "sed -e s/passed/x/ -i '' .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "perl -i -p -E 's/passed/x/' .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "bash -lc 'rm " + SNAP + "'", ["R /repo " + SNAP]),
    (HIDES, "bash -ec 'echo x > .roadworthy/state'", ["W /repo .roadworthy/state"]),
    (HIDES, 'echo "rm ' + SNAP + '" | sh', ["R /repo " + SNAP]),
    (HIDES, "cat <<'E' | bash" + NL + "rm " + SNAP + NL + "E", ["R /repo " + SNAP]),
    (HIDES, "bash -s -- a <<E" + NL + "rm " + SNAP + NL + "E", ["R /repo " + SNAP]),
    (HIDES, "curl -s http://x | sh", ["U /repo /repo"]),
    (HIDES, "trap 'rm " + SNAP + "' EXIT", ["R /repo " + SNAP]),
    (HIDES, "echo x 1<>.roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "echo x >! .roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "echo x >&.roadworthy/gates", ["W /repo .roadworthy/gates"]),
    (HIDES, "exec 3>.roadworthy/state", ["W /repo .roadworthy/state"]),
    (HIDES, "echo x > $'.roadworthy/st\\x61te'", ["W /repo .roadworthy/state"]),
    (HIDES, "time -p rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "X+=1 rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "a[0]=1 rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "function f { rm " + SNAP + "; }; f", ["R /repo " + SNAP]),
    (HIDES, "case x in x) rm " + SNAP + ";; esac", ["R /repo " + SNAP]),
    (HIDES, "{rm," + SNAP + "}", ["R /repo " + SNAP]),
    (HIDES, "noglob rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "coproc rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "ls | rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, 'c="rm ' + SNAP + '"; $c', ["R /repo " + SNAP]),
    (HIDES, "d=/tmp; declare d=.roadworthy; rm $d/plan.snapshot", ["R /repo " + SNAP]),
    (HIDES, "rm ${NOPE_XYZ:-" + SNAP + "}", ["R /repo " + SNAP]),
    (HIDES, "echo $[1<<2]" + NL + "rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, 'x="$(cat <<' + Q + 'E' + Q + NL + '"' + NL + 'E' + NL + ')"; rm ' + SNAP, ["R /repo " + SNAP]),
    (HIDES, "eval 'cd .roadworthy'; rm plan.snapshot", ["R /repo/.roadworthy plan.snapshot"]),
    (HIDES, "pushd /tmp; popd; rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "cd /tmp; cd -; rm " + SNAP, ["R /repo " + SNAP]),
    (HIDES, "rm .roadworthy{/state,/gates}", ["R /repo .roadworthy/state", "R /repo .roadworthy/gates"]),
    (HIDES, "touch .roadworthy/{state,gates}", ["W /repo .roadworthy/state", "W /repo .roadworthy/gates"]),
    (HIDES, "mv " + SNAP + "{,.bak}", ["R /repo " + SNAP, "W /repo " + SNAP + ".bak"]),
    (HIDES, "curl -so .roadworthy/state file:///etc/hosts", ["W /repo .roadworthy/state"]),
    (HIDES, "tar -cf .roadworthy/state README.md", ["W /repo .roadworthy/state"]),
    (HIDES, "gzip .roadworthy/state", ["R /repo .roadworthy/state"]),
    (HIDES, "sort -o .roadworthy/gates README.md", ["W /repo .roadworthy/gates"]),
    (HIDES, "cp README.md .roadworthy/", ["W /repo .roadworthy/"]),
    # A program that opens the file itself, handed a file of the rite: the other rule (kind N).
    (HIDES, "vim .roadworthy/scope", ["N /repo .roadworthy/scope"]),
    (HIDES, "shred -u .roadworthy/state", ["N /repo .roadworthy/state"]),
    (HIDES, "patch .roadworthy/gates /dev/null", ["N /repo .roadworthy/gates", "U /repo /repo"]),
    (HIDES, "openssl enc -in a -out .roadworthy/state", ["N /repo .roadworthy/state"]),
    (HIDES, "chmod 000 .roadworthy/gates", ["N /repo .roadworthy/gates"]),
    (HIDES, "$tool .roadworthy/state", ["N /repo .roadworthy/state"]),
    # the same directory, spelled in another case (a case-insensitive disk makes them one)
    (HIDES, "vim .Roadworthy/scope", ["N /repo .Roadworthy/scope"]),
    (HIDES, 'D=.ROADWORTHY; for d in $D; do rm $d/state; done', ["D /repo /repo", "N /repo .roadworthy"]),
    (HIDES, 'python3 -c "open(' + Q + '.Roadworthy/state' + Q + ',' + Q + 'w' + Q + ').write(' + Q + 'passed' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    # An interpreter handed the rite: inline code that writes through a path naming the directory.
    (HIDES, 'python3 -c "open(' + Q + '.roadworthy/scope' + Q + ',' + Q + 'a' + Q + ').write(' + Q + 'x' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "python3 - <<'PY'" + NL + "import os" + NL + "os.remove('.roadworthy/plan.snapshot')" + NL + "PY", ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "p=' + Q + '.road' + Q + '+' + Q + 'worthy/scope' + Q + '; open(p,' + Q + 'a' + Q + ').write(' + Q + 'x' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "import pathlib; d=pathlib.Path(' + Q + '.roadworthy' + Q + '); (d/' + Q + 'state' + Q + ').write_text(' + Q + 'passed' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "import shutil; shutil.rmtree(' + Q + '.roadworthy' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "import os; os.system(' + Q + 'rm .roadworthy/state' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "open((' + Q + '.roadworthy/state' + Q + '"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "import os; os.replace(' + Q + '/tmp/forged' + Q + ', ' + Q + '.roadworthy/plan.snapshot' + Q + ')"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "import subprocess; subprocess.run([' + Q + 'rm' + Q + ', ' + Q + '.roadworthy/state' + Q + '])"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, 'python3 -c "from pathlib import Path; p = Path(' + Q + '.roadworthy' + Q + ') / ' + Q + 'state' + Q + '; p.unlink()"', ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "node -e \"require('fs').appendFileSync('.roadworthy/scope','x')\"", ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "perl -e 'open(F,\">\",\".roadworthy/scope\")'", ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "ruby -e 'File.write(\".roadworthy/state\", \"passed\")'", ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "awk 'BEGIN { print \"passed\" > \".roadworthy/state\" }'", ["N /repo .roadworthy/.interpreter"]),
    (HIDES, "echo \"open('.roadworthy/state','w').write('passed')\" | python3", ["N /repo .roadworthy/.interpreter"]),
    # A commit and what the same command stages: which repository, and what goes in beyond the index.
    (EXACT, "git commit -q -m 'x > y'", ["C /repo -"]),
    (EXACT, "git commit -am msg", ["C /repo -a"]),
    (EXACT, "git add -A && git commit -m msg", ["A /repo *", "C /repo -"]),
    (EXACT, "git add src lib/x.py; git -C /other commit -m msg -- docs/a.md", ["A /repo src", "A /repo lib/x.py", "C /other -", "C /other docs/a.md"]),
    (READS, "git commit --dry-run", []),
    (READS, "git log --grep 'git commit' | head", []),
    (HIDES, "ln -s .roadworthy rw; rm rw/plan.snapshot", ["N /repo .roadworthy", "W /repo rw", "R /repo rw/plan.snapshot"]),
    # What cannot be followed, in a command that names the rite's directory: N on the directory.
    (HIDES, "d=/tmp; for d in .roadworthy; do rm $d/plan.snapshot; done", ["D /repo /repo", "N /repo .roadworthy"]),
    (HIDES, "x=$(echo .roadworthy/state); rm $x", ["D /repo /repo", "N /repo .roadworthy"]),
    (HIDES, 'cd "$x" && rm plan.snapshot; cat .roadworthy/state', ["R /repo plan.snapshot", "N /repo .roadworthy"]),
    (HIDES, "ls .roadworthy/* | xargs rm", ["D /repo /repo", "N /repo .roadworthy/*", "N /repo .roadworthy"]),
    (HIDES, "eval " * 10 + "rm " + SNAP, ["X /repo /repo", "N /repo .roadworthy"]),
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
    (EXACT, "bash skills/plan/scripts/scope-write.sh docs/plans/p.md --base abc", ["S /repo /repo/docs/plans/p.md"]),
    (EXACT, "skills/plan/scripts/scope-write.sh --root /r docs/plans/p.md", ["S /r /repo/docs/plans/p.md"]),
    (EXACT, "bash x/scope-write.sh --root /r docs/plans/p.md", ["S /r /repo/docs/plans/p.md"]),
    (EXACT, "cd /r && bash /p/scope-write.sh ~/.claude/plans/p.md", ["S /r /h/.claude/plans/p.md"]),
    (EXACT, 'bash x/scope-write.sh "$PLAN_UNSET"', ["S /repo ?"]),
    (EXACT, "bash skills/close/scripts/close.sh --human all approved --by owner", ["H /repo human"]),
    (EXACT, "skills/close/scripts/close.sh --human 'the label' rejected --by me --note no", ["H /repo human"]),
    (READS, "bash skills/close/scripts/close.sh --human", []),
    (READS, "bash skills/close/scripts/close.sh --needs-human 'the label on the device'", []),
    (READS, "bash skills/close/scripts/close.sh --state", []),
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

# A glob is what it matches on disk, as it is to the shell: `.roadworth?/plan.snapshot` names the
# snapshot. These rows need a directory that exists.
GD="$TMP/glob"; mkdir -p "$GD/.roadworthy"; : > "$GD/.roadworthy/plan.snapshot"; : > "$GD/.roadworthy/state"
GR="$(cd "$GD" && pwd -P)"
globbed() { RW_CMD="$1" python3 "$ROOT/hooks/shellread.py" "$GR" | cut -f1,3 | tr '\t' ' ' | sort | tr '\n' ';'; }
[ "$(globbed 'rm .roadworth?/plan.snapshot')" = "R $GR/.roadworthy/plan.snapshot;" ] && ok "a ? in a removal names the file it matches" || fail "a write hid behind a glob: $(globbed 'rm .roadworth?/plan.snapshot')"
[ "$(globbed 'rm .r*/plan.snapshot')" = "R $GR/.roadworthy/plan.snapshot;" ] && ok "so does a *" || fail "a write hid behind a glob: $(globbed 'rm .r*/plan.snapshot')"
[ "$(globbed 'echo x > .roadworthy/stat[e]')" = "W $GR/.roadworthy/state;" ] && ok "and a [ ] in the target of a redirection" || fail "a write hid behind a glob: $(globbed 'echo x > .roadworthy/stat[e]')"
[ "$(globbed 'gedit .roadworth?/state')" = "N $GR/.roadworthy/state;" ] && ok "a glob handed to an unknown command is matched against the rite's directory too" || fail "a write hid behind a glob (kind N): $(globbed 'gedit .roadworth?/state')"
[ -z "$(globbed 'ls .roadworth?/')" ] && ok "and a glob handed to a reader is a read" || fail "a read was taken for a write (a glob to ls): $(globbed 'ls .roadworth?/')"

# It never raises. A string that cannot be read is said to be unreadable (kind X), which the gate
# treats as a write it could not rule out; the alternative is a guard that crashes on its input.
python3 - "$ROOT/hooks" <<'PY' && ok "two thousand unterminated substitutions, a lone quote and an open heredoc do not raise" || fail "the reader raised on malformed input"
import sys
sys.dont_write_bytecode = True
sys.path.insert(0, sys.argv[1])
from shellread import targets
assert targets('"$(' * 2000, "/x") == [("X", "/x", "/x")], "deep nesting is not said to be unreadable"
for bad in ("'", '"', "cat <<EOF", "$(", "`", "((", "[[ a", "echo ${", "", "|||", ">", "a >", "$'", "<<", "x=$((", "for", "case x in"):
    targets(bad, "/x")
PY

rw_end
