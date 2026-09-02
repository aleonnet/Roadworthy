#!/usr/bin/env bash
# close.sh — run the declared gates after the last commit and record the evidence.
#
# Gates live in .roadworthy/gates, one shell command per line (`#` comments).
# Each gate is recorded in the evidence ledger as JSON:
#   {ts, head, wtree, cmd, cmd_sha256, exit, tail}
# The ledger lives in $ROADWORTHY_DATA (default: $CLAUDE_PLUGIN_DATA, else .roadworthy)
# as evidence.jsonl. A record is FRESH when its wtree equals the current content
# fingerprint, STALE otherwise, MISSING when no record exists for the command.
#
# Usage:
#   close.sh               run all gates (requires a clean tree); exit 0 = passed
#   close.sh --check       classify each gate FRESH | STALE | MISSING for the current tree
#   close.sh --needs-human "<item>"   record that a person must verify <item>; state needs_human
#   close.sh --state       print the last recorded state: passed | gaps_found | needs_human
set -uo pipefail
root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "close: not a git repository" >&2; exit 1; }
cd "$root" || exit 1
gates=".roadworthy/gates"
data="${ROADWORTHY_DATA:-${CLAUDE_PLUGIN_DATA:-$root/.roadworthy}}"
mkdir -p "$data"
ledger="$data/evidence.jsonl"
state_file="$data/state"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fp() { bash "$here/tree-fingerprint.sh" "$root"; }

record() { # cmd exit tail
  python3 - "$ledger" "$1" "$2" "$3" "$(fp)" <<'PY'
import hashlib, json, sys, time
ledger, cmd, rc, tail, fp = sys.argv[1:6]
head, wtree, state = fp.split()
with open(ledger, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "head": head, "wtree": wtree,
                         "cmd": cmd, "cmd_sha256": hashlib.sha256(cmd.encode()).hexdigest(),
                         "exit": int(rc), "tail": tail[-800:]}) + "\n")
PY
}

case "${1:-}" in
  --state) cat "$state_file" 2>/dev/null || echo "none"; exit 0 ;;
  --needs-human)
    item="${2:?--needs-human needs an item}"
    echo "needs_human" > "$state_file"
    record "needs-human: $item" 0 "$item"
    echo "close: needs_human — $item"; exit 0 ;;
  --check)
    [ -f "$gates" ] || { echo "close: no $gates"; exit 0; }
    read -r _ wtree _ <<< "$(fp)"
    fail=0
    while IFS= read -r cmd; do
      [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
      status="$(python3 - "$ledger" "$cmd" "$wtree" <<'PY'
import json, sys, os
ledger, cmd, wtree = sys.argv[1:4]
last = None
if os.path.exists(ledger):
    for line in open(ledger, encoding="utf-8"):
        r = json.loads(line)
        if r["cmd"] == cmd: last = r
if last is None: print("MISSING")
elif last["wtree"] == wtree and last["exit"] == 0: print("FRESH")
elif last["wtree"] == wtree: print("FRESH-RED")
else: print("STALE")
PY
)"
      printf '  %-9s %s\n' "$status" "$cmd"
      [ "$status" = "FRESH" ] || fail=1
    done < "$gates"
    exit $fail ;;
  "") ;;
  *) echo "close: unknown argument $1" >&2; exit 1 ;;
esac

[ -f "$gates" ] || { echo "close: no $gates — declare the gates first"; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
  echo "close: the tree is dirty; commit first — a gate measured before the last commit is not a gate of this closing"
  echo "gaps_found" > "$state_file"; exit 1
fi
read -r head wtree _ <<< "$(fp)"
echo "close: HEAD $head · tree $wtree"
failed=0
while IFS= read -r cmd; do
  [[ "$cmd" =~ ^[[:space:]]*(#|$) ]] && continue
  out="$(bash -c "$cmd" 2>&1)"; rc=$?
  record "$cmd" "$rc" "$out"
  if [ $rc -eq 0 ]; then printf '  OK    %s\n' "$cmd"; else printf '  FAIL  %s (exit %s)\n' "$cmd" "$rc"; printf '%s\n' "$out" | tail -5 | sed 's/^/        /'; failed=$((failed + 1)); fi
done < "$gates"
if [ $failed -eq 0 ]; then
  echo "passed" > "$state_file"
  rm -f .roadworthy/scope
  echo "close: passed — evidence in $ledger; scope released"
else
  echo "gaps_found" > "$state_file"
  echo "close: gaps_found — $failed gate(s) red; scope kept"; exit 1
fi
