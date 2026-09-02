#!/usr/bin/env bash
# refute-ledger.sh — every test that calls itself a fence must carry its refutation.
#
# A file is a fence when its first 3 lines match --marker (default: FENCE|GUARD|CERCA,
# case-insensitive). A fence must contain a refutation record matching --record
# (default: refut|inject|Actual:) anywhere in the file. Files listed with --legacy are
# tolerated (declared debt, never silent), and the legacy list may only shrink: its
# size is printed so a gate can pin it. A file whose first 6 lines match --exclude declares
# itself a diagnostic (dump, probe, spike), not a guarantee, and is skipped (default: none).
# Usage: refute-ledger.sh <test dir> [--marker <regex>] [--record <regex>] [--legacy <file>] [--exclude <regex>]
set -euo pipefail
dir="${1:?usage: refute-ledger.sh <test dir> [--marker re] [--record re] [--legacy file]}"; shift
marker='FENCE|GUARD|CERCA'; record='refut|inject|Actual:'; legacy=""; exclude=""
while [ $# -gt 0 ]; do
  case "$1" in
    --marker) marker="$2"; shift 2 ;;
    --record) record="$2"; shift 2 ;;
    --legacy) legacy="$2"; shift 2 ;;
    --exclude) exclude="$2"; shift 2 ;;
    *) echo "refute-ledger: unknown argument $1" >&2; exit 1 ;;
  esac
done
[ -d "$dir" ] || { echo "refute-ledger: $dir is not a directory" >&2; exit 1; }
fail=0; fences=0; tolerated=0
while IFS= read -r -d '' f; do
  head -3 "$f" | grep -q -i -E "$marker" || continue
  if [ -n "$exclude" ] && head -6 "$f" | grep -q -i -E "$exclude"; then continue; fi
  fences=$((fences + 1))
  if grep -q -i -E "$record" "$f"; then continue; fi
  if [ -n "$legacy" ] && grep -q -F -x "$f" "$legacy"; then tolerated=$((tolerated + 1)); continue; fi
  echo "  [FAIL] $f: declares itself a fence and carries no refutation record ($record)"
  fail=$((fail + 1))
done < <(find "$dir" -type f \( -name '*_test.*' -o -name 'test_*' -o -name '*.test.*' -o -name '*_spec.*' \) -print0 | sort -z)
echo "refute-ledger: $fences fence(s), $tolerated legacy, $fail without a record"
[ "$fail" -eq 0 ]
