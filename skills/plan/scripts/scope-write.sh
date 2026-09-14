#!/usr/bin/env bash
# scope-write.sh — open a front from an approved plan, mechanically.
#
# The first act of EXECUTION, never of planning: it reads the plan's Scope and Verification
# sections and writes, in one act,
#   .roadworthy/scope          the globs the scope lock will enforce
#   .roadworthy/gates          the commands close.sh will run, one per line
#   .roadworthy/plan.snapshot  what was approved: plan, base HEAD, globs, gates, and digests
#
# Why the snapshot. close.sh used to re-read .roadworthy/gates at closing time, so editing the
# Verification section after approval silently changed what "the gates passed" meant. The snapshot
# is taken once, at the moment the front opens, and the closing is measured against it.
#
# The digests cover `scope`, `gates` and the snapshot's own CANONICAL FORM -- the snapshot JSON
# without the `digests` field, keys sorted, no spaces. A file cannot contain its own digest; it can
# contain the digest of its canonical part.
#
# Both sections are read as FENCED BLOCKS, never as prose bullets: close.sh executes each gate line
# with `bash -c`, and `- \`cmd\` → expected result` is not a command. One grammar, and it is the one
# the machine can run.
#
# REOPENING a front keeps its base. The base HEAD is what close.sh measures the front's diff
# against, so taking it from the current HEAD is right when a front OPENS and wrong when one is
# reopened mid-flight -- which happens whenever an execution decision changes the plan's
# Verification block. Measured on 2026-09-14: reopening after 23 commits would have set the base
# to the tip and left the out-of-scope check with an empty diff to look at, silently. `--base`
# carries the real one; without it the base is HEAD, which stays the common case.
#
# Usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>]
set -euo pipefail
plan="${1:?usage: scope-write.sh <plan.md> [--root <repository>] [--base <ref>]}"; shift || true
root=""; base=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    *) echo "scope-write: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -f "$plan" ] || { echo "scope-write: plan not found: $plan" >&2; exit 1; }
[ -n "$root" ] || root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "scope-write: not a git repository; give --root" >&2; exit 1; }
cd "$root"

python3 - "$plan" "$base" <<'PY'
import hashlib, json, os, re, subprocess, sys, time

plan = sys.argv[1]
base_arg = sys.argv[2] if len(sys.argv) > 2 else ""
text = open(plan, encoding="utf-8").read()

def fenced(*titles):
    """The first fenced block of the first section whose heading starts with one of `titles`."""
    for line_no, line in enumerate(text.splitlines()):
        if not line.startswith("## "):
            continue
        head = line[3:].strip().lower()
        if not any(head.startswith(t) for t in titles):
            continue
        rest = text.splitlines()[line_no + 1:]
        block, inside = [], False
        for l in rest:
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

globs = fenced("scope", "escopo")
gates = fenced("verification", "verificação", "verificacao")
missing = []
if globs is None: missing.append("a '## Scope' ('## Escopo') section with a fenced block")
if gates is None: missing.append("a '## Verification' ('## Verificação') section with a fenced block")
if missing:
    sys.stderr.write("scope-write: the plan is missing " + "; and ".join(missing) +
                     ".\nBoth are read as fenced blocks, never as prose: close.sh runs each gate line "
                     "with `bash -c`, and a bullet like `- `cmd` -> expected` is not a command.\n")
    sys.exit(1)
if not globs: sys.stderr.write("scope-write: the Scope block is empty; a front with no scope is not a front.\n"); sys.exit(1)
if not gates: sys.stderr.write("scope-write: the Verification block declares no gate; close.sh cannot close without one.\n"); sys.exit(1)

os.makedirs(".roadworthy", exist_ok=True)
name = os.path.basename(plan)
banner = (f"# Written by scope-write.sh from {name}. Do not edit by hand: the closing is measured\n"
          f"# against .roadworthy/plan.snapshot, and a hand edit here only makes the digests disagree.\n")
with open(".roadworthy/scope", "w", encoding="utf-8") as fh:
    fh.write(banner + "\n".join(globs) + "\n")
with open(".roadworthy/gates", "w", encoding="utf-8") as fh:
    fh.write(banner + "\n".join(gates) + "\n")

def sha(path):
    return hashlib.sha256(open(path, "rb").read()).hexdigest()

ref = base_arg or "HEAD"
r = subprocess.run(["git", "rev-parse", "--verify", "--quiet", ref + "^{commit}"],
                   capture_output=True, text=True)
if r.returncode != 0:
    sys.stderr.write("scope-write: base %s does not resolve to a commit here.\n" % ref); sys.exit(1)
head = r.stdout.strip()
snap = {"ts": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "plan": os.path.abspath(plan), "plan_name": name,
        "base_head": head, "scope_globs": globs, "gates": gates}
canonical = json.dumps(snap, sort_keys=True, separators=(",", ":"))
snap["digests"] = {"scope": sha(".roadworthy/scope"),
                   "gates": sha(".roadworthy/gates"),
                   "snapshot_canonical": hashlib.sha256(canonical.encode()).hexdigest()}
with open(".roadworthy/plan.snapshot", "w", encoding="utf-8") as fh:
    json.dump(snap, fh, indent=1, ensure_ascii=False)
    fh.write("\n")

print(f"scope-write: front open from {name}")
print(f"  base HEAD  {head[:12] or '(no commits)'}")
print(f"  scope      {len(globs)} glob(s) -> .roadworthy/scope")
print(f"  gates      {len(gates)} command(s) -> .roadworthy/gates")
print(f"  snapshot   .roadworthy/plan.snapshot")
PY
