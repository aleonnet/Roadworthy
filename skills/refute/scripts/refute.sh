#!/usr/bin/env bash
# refute.sh — inject a defect, expect the check to fail for that reason, restore by hash.
#
# Usage:
#   refute.sh --file <path> (--sed <expr> | --patch <file>) --expect <text> -- <check command...>
#
# Exit 0 only if: the check exits non-zero, its output contains <text>, and the
# file is restored with an identical SHA-256. Anything else exits 1 and says why.
set -euo pipefail

file="" sed_expr="" patch_file="" expect=""
while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="$2"; shift 2 ;;
    --sed) sed_expr="$2"; shift 2 ;;
    --patch) patch_file="$2"; shift 2 ;;
    --expect) expect="$2"; shift 2 ;;
    --) shift; break ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "refute: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -n "$file" ] && [ -f "$file" ] || { echo "refute: --file is required and must exist" >&2; exit 1; }
[ -n "$sed_expr" ] || [ -n "$patch_file" ] || { echo "refute: --sed or --patch is required" >&2; exit 1; }
[ -n "$expect" ] || { echo "refute: --expect is required (the failure text that proves the intended assertion fired)" >&2; exit 1; }
[ $# -gt 0 ] || { echo "refute: give the check command after --" >&2; exit 1; }

hash() { shasum -a 256 "$1" | cut -d' ' -f1; }
snapshot="$(mktemp -d)"
cp -p "$file" "$snapshot/original"
before="$(hash "$file")"
restore() {
  cp -p "$snapshot/original" "$file"
  if [ "$(hash "$file")" != "$before" ]; then
    echo "refute: RESTORE FAILED for $file — hash differs; original kept at $snapshot/original" >&2
    exit 1
  fi
  rm -rf "$snapshot"
}
trap restore EXIT

if [ -n "$sed_expr" ]; then
  sed -i.refute-bak -e "$sed_expr" "$file" && rm -f "$file.refute-bak"
else
  patch -s "$file" "$patch_file"
fi
if [ "$(hash "$file")" = "$before" ]; then
  echo "refute: the injection changed nothing in $file — the defect was not applied" >&2
  exit 1
fi

set +e
output="$("$@" 2>&1)"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  echo "refute: FAILED — the check stayed green with the defect injected (it cannot catch: $expect)" >&2
  exit 1
fi
if ! printf '%s' "$output" | grep -q -F -- "$expect"; then
  echo "refute: FAILED — the check went red, but not for the intended reason. Expected text: '$expect'. Output tail:" >&2
  printf '%s\n' "$output" | tail -15 >&2
  exit 1
fi
# Restore now (the EXIT trap would do it too) and prove the check is green on
# the clean file: red-on-defect without green-on-clean proves nothing.
restore; trap - EXIT
set +e
"$@" >/dev/null 2>&1
rc_clean=$?
set -e
if [ "$rc_clean" -ne 0 ]; then
  echo "refute: FAILED — the check is also red on the clean file (exit $rc_clean); it does not measure the defect" >&2
  exit 1
fi
# The record is written by THIS script, never by the agent: a refutation that exists only as a
# sentence in a report is the thing this tool exists to replace. It carries both exit codes and
# both hashes, so the claim can be checked without trusting anyone.
# The same rule as rw_data_dir in hooks/lib.sh: ROADWORTHY_DATA when set, else the project.
# CLAUDE_PLUGIN_DATA is per plugin and shared by every project; a refutation record belongs to
# the repository whose file was refuted.
data="${ROADWORTHY_DATA:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)/.roadworthy}"
if mkdir -p "$data" 2>/dev/null; then
  after="$(hash "$file")"
  python3 - "$data/refutations.jsonl" "$file" "$before" "$after" "$sed_expr$patch_file" "$expect" "$rc" "$rc_clean" "$*" <<'PY' || true
import json, subprocess, sys, time
ledger, f, before, after, injection, expect, red, clean, cmd = sys.argv[1:10]
try:
    w = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], capture_output=True, text=True).stdout.strip()
except Exception:
    w = ""
with open(ledger, "a", encoding="utf-8") as fh:
    fh.write(json.dumps({"ts": time.strftime("%Y-%m-%dT%H:%M:%S"), "file": f,
                         "sha_before": before, "sha_after": after, "restored": before == after,
                         "injection": injection, "expect": expect,
                         "exit_red": int(red), "exit_clean": int(clean),
                         "check_cmd": cmd, "head": w}) + "\n")
PY
fi
echo "refute: OK — red with the defect ('$expect', exit $rc), green on the clean file, $file restored (hash verified)"
[ -f "$data/refutations.jsonl" ] && echo "refute: recorded in $data/refutations.jsonl"
