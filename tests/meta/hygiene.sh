#!/usr/bin/env bash
# hygiene
# Run alone: bash tests/meta/hygiene.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── shell hygiene ────────────────────────────────────────────────────────────
# The fences are listed BY NAME, never by glob: `hooks/*` would sweep in hooks.json (which takes no
# comment header) and quietly cover a file nobody meant to check. The suite's own files ARE globbed,
# because there the glob is the point: a case that exists must be checked, and tests/cases.txt is
# what refuses a case file nobody declared.
section "shell syntax"
RW_FENCES="hooks/lib.sh hooks/principles hooks/protect-paths hooks/scope-lock hooks/guard-commit hooks/plan-review-gate hooks/overnight-guard hooks/rite-gate hooks/stop-gate"
# shellcheck disable=SC2086  # the two lists are deliberately word-split into arguments.
RW_SUITE="tests/run.sh tests/lib.sh tests/attack.sh $(echo tests/fixtures/*.sh tests/hooks/*.sh tests/scripts/*.sh tests/meta/*.sh)"
for f in $RW_FENCES skills/*/scripts/*.sh $RW_SUITE; do
  bash -n "$f" && ok "bash -n $f" || fail "bash -n $f"
done
if command -v shellcheck >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  shellcheck -S warning -x $RW_FENCES skills/*/scripts/*.sh $RW_SUITE \
    && ok "shellcheck (warning)" || fail "shellcheck"
else
  echo "  [SKIP] shellcheck not installed"
fi
python3 -c 'import json; json.load(open(".claude-plugin/plugin.json")); json.load(open(".claude-plugin/marketplace.json")); json.load(open("hooks/hooks.json"))' \
  && ok "manifests are valid JSON" || fail "manifest JSON"

# ── the python inside the shell ──────────────────────────────────────────────
# Most of the plugin's logic is Python embedded in bash heredocs, which `bash -n` and shellcheck
# never read. 0.6.0's CHANGELOG said the suite compiles every Python script and names every import
# nobody uses; measured on 2026-09-14, nothing here did either. This does: every `python3 - <<'TAG'`
# block in the fences and the scripts, plus the standalone Python files, is compiled, and an import
# no name in the block uses is a failure that names the file and the name.
section "python: every embedded block compiles, and no import is dead"
cat > "$TMP/pycheck.py" <<'PY'
import ast, re, sys
OPEN = re.compile(r"python3?\s+-\s.*<<\s*'?([A-Z][A-Z0-9_]*)'?\s*$")
def blocks(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    if path.endswith((".py",)) or open(path, "rb").read(2) == b"#!" and "python" in text.splitlines()[0]:
        yield path, text, 1
        return
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        m = OPEN.search(lines[i])
        if m:
            tag, start = m.group(1), i + 1
            j = start
            while j < len(lines) and lines[j].strip() != tag:
                j += 1
            yield "%s:%d" % (path, start + 1), "\n".join(lines[start:j]), start + 1
            i = j
        i += 1
def dead_imports(tree):
    imported = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for a in node.names: imported[(a.asname or a.name).split(".")[0]] = node.lineno
        elif isinstance(node, ast.ImportFrom):
            for a in node.names: imported[a.asname or a.name] = node.lineno
    used = {n.id for n in ast.walk(tree) if isinstance(n, ast.Name)}
    return sorted(n for n in imported if n not in used)
problems = 0
for path in sys.argv[1:]:
    for name, src, first in blocks(path):
        try:
            tree = ast.parse(src, name)
        except SyntaxError as e:
            print("  [FAIL] %s does not compile: %s" % (name, e)); problems += 1; continue
        for dead in dead_imports(tree):
            print("  [FAIL] %s: import nobody uses: %s" % (name, dead)); problems += 1
sys.exit(1 if problems else 0)
PY
# shellcheck disable=SC2086
if python3 "$TMP/pycheck.py" $RW_FENCES skills/*/scripts/*.sh bin/rw-metrics hooks/globmatch.py tests/goldens/check.py > "$TMP/py.out" 2>&1; then
  ok "every embedded block and standalone script compiles, and no import is dead"
else
  fail "python hygiene"; cat "$TMP/py.out"
fi
# The check has to be able to say no: a planted dead import, in a block and in a script.
printf 'x=1\npython3 - <<'"'"'PY'"'"'\nimport os, sys\nprint(sys.argv)\nPY\n' > "$TMP/planted.sh"
python3 "$TMP/pycheck.py" "$TMP/planted.sh" > "$TMP/planted.out" 2>&1 \
  && fail "a dead import passed (planted os in an embedded block)" \
  || { grep -q 'import nobody uses: os' "$TMP/planted.out" && ok "a dead import in an embedded block is named" || fail "a dead import passed: wrong reason: $(cat "$TMP/planted.out")"; }
printf 'import json\nprint(1\n' > "$TMP/broken.py"
python3 "$TMP/pycheck.py" "$TMP/broken.py" > "$TMP/broken.out" 2>&1 \
  && fail "a script that does not compile passed" \
  || { grep -q 'does not compile' "$TMP/broken.out" && ok "a script that does not compile is named" || fail "broken script: wrong reason"; }

# ── run-hook.cmd: the batch half without bash ────────────────────────────────
# cmd.exe runs the batch half on Windows and hands the hook to bash. Without bash, 0.6.0's
# CHANGELOG said it "warns and refuses" while the file exited 0 in silence (measured 2026-09-14).
# This gate cannot execute cmd.exe; it reads the text, and .github/workflows/ci.yml executes it on
# a Windows runner with every bash hidden. The policy is the hook's own crash policy: a guard that
# cannot run refuses (exit 2 blocks the call); principles and stop-gate warn (exit 1), because
# exit 2 there erases the prompt or traps the session.
section "run-hook.cmd: without bash, a guard refuses and the two non-guards warn"
batch="$(sed -n '2,/^CMDBLOCK$/p' hooks/run-hook.cmd)"
printf '%s' "$batch" | grep -q 'exit /b 0' \
  && fail "run-hook.cmd fails open without bash (exit /b 0 in the batch half)" || ok "no exit /b 0 anywhere in the batch half"
printf '%s' "$batch" | grep -q 'no bash' && printf '%s' "$batch" | grep -q '^exit /b 2' \
  && printf '%s' "$batch" | grep -q -i '"principles" exit /b 1' && printf '%s' "$batch" | grep -q -i '"stop-gate" exit /b 1' \
  && ok "the no-bash branch warns, refuses with 2 for guards and warns with 1 for principles and stop-gate" || fail "the no-bash policy is not per hook"
grep -q 'windows-no-bash' .github/workflows/ci.yml && ok "and the CI executes that branch on a Windows runner" || fail "no Windows job executes the no-bash branch"

rw_end
