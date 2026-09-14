#!/usr/bin/env bash
# plan-preflight.sh — check a plan mechanically, before anyone reads it.
#
# Written because five rounds of cold review on one plan never converged, and the measured cause
# was not the reviewer: it was that every round spent its attention on things a machine can check.
# A citation that does not resolve, a scope path that does not exist, an acceptance table that
# skips a number, a file the plan claims to have read and never opened -- none of that needs
# judgement, and all of it was arriving at the reviewer.
#
# What it checks:
# READ AGAINST THE BASE, NOT AGAINST THE TREE. A plan is written against a ref, and by the time
# it is checked the tree has usually moved -- often because the plan itself was being executed.
# Checking citations against the working tree turns every finished correction into a false alarm
# and, worse, invites editing the plan to match the code, which is the record following the work
# instead of the other way round. The base comes from --base, else the plan's `base:` line, else
# .roadworthy/plan.snapshot, else it is the working tree. skills/plan/SKILL.md already orders the
# reading itself to be done against the base; this is the same rule, mechanised.
#
#   1. CITATIONS, by content. A line of the form `path:line — \`literal\`` must resolve AND the line
#      must contain that literal. Checking that the file and line merely EXIST is what let a false
#      citation be signed: the strongest form of this rule is the one that compares the text.
#   2. REFERENCES. Any other `path:line` must resolve and be inside the file. Weaker on purpose,
#      and the report says so: a reference does not sustain a claim, a citation does.
#   3. SCOPE. Every path in the Scope block exists, or is declared among the new files.
#   4. ACCEPTANCE. The numbers in the acceptance table run 1..N with no gap and no repeat --
#      sliced by section, because a table elsewhere in the plan is not the acceptance table.
#   5. READING. Every existing scope path was read WHOLE in this session, proved from the
#      transcript. Not "claims to have read": a Read with no window, or a command that prints the
#      file entire. The transcript is written by the harness, not by the author.
#   6. CORRECTIONS. Each declared correction names a path and the literal it replaces; before the
#      work, that literal must still be there (otherwise the plan is describing something that is
#      not the case). With --closing, it must be GONE -- which is how "I fixed it" stops being a
#      sentence.
#   7. COMMANDS. Every command in the impact sweep appears in the session transcript.
#
# What it does NOT check: whether the plan is a good idea. That is what a reader is for, and it is
# the only thing a reader should be spending attention on.
#
# Refuted 2026-09-14, six times, each injection restored and its SHA-256 verified
# (skills/refute/scripts/refute.sh, records in .roadworthy/refutations.jsonl):
#   the content comparison removed  -> tests/run.sh red with `false citation passed`
#   the whole-reading check removed -> red with `unread file not named`
#   the closing check removed       -> red with `undone correction passed`
#   the base ignored, tree read     -> red with `the base was ignored`
#   `head -N` counted as a reading  -> red with `a window passed as a reading`
#   newline dropped as a separator  -> red with `green plan rejected`
# Each went green again on the clean file, which is the half that proves the check measures
# the defect and not the weather.
#
# Usage: plan-preflight.sh <plan.md> [--root <repo>] [--transcript <file>] [--base <ref>]
#                          [--closing] [--quiet]
set -euo pipefail
plan="${1:?usage: plan-preflight.sh <plan.md> [--root <repo>] [--transcript <file>] [--base <ref>] [--closing]}"; shift || true
root=""; transcript=""; closing=0; quiet=0; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --transcript) transcript="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --closing) closing=1; shift ;;
    --quiet) quiet=1; shift ;;
    *) echo "plan-preflight: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -f "$plan" ] || { echo "plan-preflight: plan not found: $plan" >&2; exit 1; }
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

RW_CLOSING="$closing" RW_QUIET="$quiet" python3 - "$plan" "$root" "$transcript" "$base" <<'PY'
import json, os, re, subprocess, sys, time

plan_path, root, transcript = sys.argv[1], sys.argv[2], sys.argv[3]
base = sys.argv[4] if len(sys.argv) > 4 else ""
closing = os.environ.get("RW_CLOSING") == "1"
quiet = os.environ.get("RW_QUIET") == "1"
text = open(plan_path, encoding="utf-8").read()
# The base, in order: the flag, the plan's own declaration, the snapshot written when the front
# opened. A base that does not resolve is an error, never a silent fall back to the tree.
if not base:
    m = re.search(r"^base:[ \t]*(\S+)", text, re.M)
    if m:
        base = m.group(1)
    else:
        snap = os.path.join(root, ".roadworthy", "plan.snapshot")
        if os.path.exists(snap):
            try:
                base = (json.load(open(snap, encoding="utf-8")) or {}).get("base_head") or ""
            except Exception:
                base = ""
if base and subprocess.run(["git", "-C", root, "rev-parse", "--verify", "--quiet", base + "^{commit}"],
                           capture_output=True).returncode != 0:
    print("plan-preflight: base %s does not resolve in %s" % (base, root), file=sys.stderr)
    sys.exit(1)
lines = text.splitlines()
problems, counts = [], {}

def bump(k, n=1):
    counts[k] = counts.get(k, 0) + n

def section(*titles):
    out, on = [], False
    for l in lines:
        if l.startswith("## "):
            head = l[3:].strip().lower()
            on = any(head.startswith(t) for t in titles)
            continue
        if on:
            out.append(l)
    return out

def fenced(sec):
    block, inside, closed = [], False, False
    for l in sec:
        if l.strip().startswith("```"):
            if inside:
                closed = True; inside = False
            elif not closed:
                inside = True
            continue
        if inside and l.strip():
            block.append(l.rstrip())
    return block

_cache = {}
def read_file(rel, tree=False):
    """The file as the plan saw it: at the base when there is one, in the tree when there is not.
    `tree=True` reads the working tree whatever the base: the closing checks that a correction was
    MADE, and what shows it made is the tree, never the base the plan was written against. Until
    0.6.1 the closing read the base too, so a plan with a `base:` line reported every one of its
    corrections NOT DONE forever (measured 2026-09-14: 42 of 42 on the plan of that release)."""
    key = (rel, tree)
    if key in _cache:
        return _cache[key]
    out = None
    if base and not tree:
        r = subprocess.run(["git", "-C", root, "show", "%s:%s" % (base, rel)],
                           capture_output=True, text=True)
        if r.returncode == 0:
            out = r.stdout.splitlines()
    else:
        p = os.path.join(root, rel)
        if os.path.exists(p):
            try:
                out = open(p, encoding="utf-8", errors="replace").read().splitlines()
            except Exception:
                out = None
    _cache[key] = out
    return out

# --- 1 and 2: citations and references ----------------------------------------------------------
CITATION = re.compile(r"^([A-Za-z0-9_.][A-Za-z0-9_./-]*):(\d+) — `(.+)`\s*$")
REFERENCE = re.compile(r"`?(\.?[A-Za-z0-9_][A-Za-z0-9_./-]*\.[A-Za-z0-9]+|hooks/[a-z-]+):(\d+)(?:-(\d+))?`?")
cited = set()
for raw in lines:
    m = CITATION.match(raw.strip())
    if not m:
        continue
    rel, n, literal = m.group(1), int(m.group(2)), m.group(3)
    cited.add((rel, n))
    src = read_file(rel)
    if src is None:
        problems.append("citation %s:%d — no such file" % (rel, n)); continue
    if n > len(src):
        problems.append("citation %s:%d — the file has %d lines" % (rel, n, len(src))); continue
    bump("citations")
    if literal.strip() not in src[n - 1]:
        problems.append("citation %s:%d does not match the line\n    the line says: %s\n    the plan says: %s"
                        % (rel, n, src[n - 1].strip()[:120], literal[:120]))
seen = set()
for m in REFERENCE.finditer(text):
    rel, a, b = m.group(1), int(m.group(2)), m.group(3)
    if (rel, a) in cited or (rel, a, b) in seen:
        continue
    seen.add((rel, a, b))
    src = read_file(rel)
    if src is None:
        continue          # a path the plan will create, or one outside the repository
    bump("references")
    hi = int(b) if b else a
    if hi > len(src):
        problems.append("reference %s:%s — the file has %d lines" % (rel, m.group(0), len(src)))

# --- 3: scope ------------------------------------------------------------------------------------
scope = fenced(section("scope", "escopo"))
declared_new = set()
for l in section("scope", "escopo"):
    if l.lower().startswith(("**new files declared:", "**arquivos novos declarados:")) or declared_new:
        declared_new |= set(re.findall(r"`([^`]+)`", l))
        if l.strip().endswith("."):
            break
existing_scope = []
for rel in scope:
    if "*" in rel or rel in declared_new:
        continue
    if not os.path.exists(os.path.join(root, rel)):
        problems.append("scope: %s does not exist and is not declared as a new file" % rel)
    else:
        existing_scope.append(rel)
bump("scope paths", len(scope))

# --- 4: acceptance numbering ---------------------------------------------------------------------
nums = [int(m.group(1)) for l in section("acceptance", "aceite")
        for m in [re.match(r"^\|\s*(\d+)\s*\|", l)] if m]
if nums and nums != list(range(1, len(nums) + 1)):
    problems.append("acceptance numbers are not 1..%d in order: %s" % (len(nums), nums))
bump("acceptance rows", len(nums))

# --- 5, 7: what the transcript proves -------------------------------------------------------------
whole_reads, ran = set(), []
if transcript and os.path.exists(transcript):
    try:
        for raw in open(transcript, encoding="utf-8", errors="replace"):
            raw = raw.strip()
            if not raw:
                continue
            try:
                rec = json.loads(raw)
            except Exception:
                continue
            content = ((rec.get("message") or {}).get("content")) or []
            if not isinstance(content, list):
                continue
            for block in content:
                if not isinstance(block, dict) or block.get("type") != "tool_use":
                    continue
                name, inp = block.get("name"), block.get("input") or {}
                if name == "Read" and inp.get("file_path") and not inp.get("offset") and not inp.get("limit"):
                    whole_reads.add(os.path.realpath(inp["file_path"]))
                elif name == "Bash" and inp.get("command"):
                    cmd = inp["command"]
                    ran.append(cmd)
                    # `cat` and `sed -n '1,$p'` print the file entire. `head -N` is a WINDOW by
                    # definition and is deliberately absent. It was listed here and, measured,
                    # matched almost nothing: the alternative ended in a space and `\s+` followed
                    # it, so `head -20 b.txt` never matched and only `head -20  b.txt`, with two
                    # spaces, did. A branch that fires on a typo is worse than no branch: it
                    # would have let a window pass as a whole reading, at random.
                    # A newline separates commands exactly as `;` does, and a shell block of several
                    # lines is the common case -- without it in the set, every reading done inside
                    # a multi-line command was invisible and the file counted as never read.
                    for mm in re.finditer(r"(?:^|[;&|\n]\s*)(?:cat|sed -n ..1,\$p.)\s+([^\s;&|]+)", cmd):
                        whole_reads.add(os.path.realpath(os.path.join(root, mm.group(1))))
    except Exception as e:
        problems.append("transcript could not be read (%s); reading and commands cannot be proved" % e)
    for rel in existing_scope:
        if os.path.realpath(os.path.join(root, rel)) not in whole_reads:
            problems.append("scope: %s was never read WHOLE in this session (a window is not a reading)" % rel)
        else:
            bump("files proved read whole")
    sweep = fenced(section("impact sweep", "varredura de impacto"))
    joined = "\n".join(ran)
    for cmd in sweep:
        cmd = cmd.split("#")[0].strip()
        if not cmd:
            continue
        bump("commands")
        if cmd not in joined:
            problems.append("impact sweep: this command is not in the session transcript: %s" % cmd[:100])
else:
    problems.append("no transcript given (--transcript): reading and commands cannot be proved, and "
                    "a plan that cannot prove what it read is a plan that asked you to take its word")

# --- 6: declared corrections ---------------------------------------------------------------------
for l in section("declared corrections", "correções declaradas", "correcoes declaradas"):
    cells = [c.strip() for c in l.strip().strip("|").split("|")] if l.strip().startswith("|") else []
    if len(cells) < 3:
        continue
    path_cell = re.findall(r"`([^`]+)`", cells[1])
    old_cell = re.findall(r"`([^`]+)`", cells[2])
    if not path_cell or not old_cell:
        continue
    rel, old = path_cell[0], old_cell[0]
    body = read_file(rel, tree=closing)
    if body is None:
        problems.append("correction: %s does not exist" % rel); continue
    bump("declared corrections")
    present = any(old in line for line in body)
    if closing and present:
        problems.append("correction NOT DONE: %s still contains %r" % (rel, old[:80]))
    if not closing and not present:
        problems.append("correction: %s does not contain %r, so the plan is describing something that "
                        "is not the case" % (rel, old[:80]))

# --- report ---------------------------------------------------------------------------------------
summary = ", ".join("%s %d" % (k, v) for k, v in sorted(counts.items())) or "nothing to check"
mode = "closing" if closing else "before the work"
if not quiet:
    print("plan-preflight (%s, base %s): %s" % (mode, base[:12] if base else "working tree", summary))
# The same rule as rw_data_dir in hooks/lib.sh: ROADWORTHY_DATA when set, else the project.
# CLAUDE_PLUGIN_DATA is per plugin and shared by every project; project evidence never goes there.
data = os.environ.get("ROADWORTHY_DATA", "").strip() or os.path.join(root, ".roadworthy")
try:
    os.makedirs(data, exist_ok=True)
    with open(os.path.join(data, "preflight.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "plan": os.path.abspath(plan_path),
                             "mode": mode, "base": base, "counts": counts, "problems": problems}) + "\n")
except Exception:
    pass
if problems:
    print("plan-preflight: %d problem(s)" % len(problems))
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("plan-preflight: green")
PY
