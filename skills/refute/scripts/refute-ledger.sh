#!/usr/bin/env bash
# refute-ledger.sh — every test that calls itself a fence must carry its refutation.
#
# A file is a fence when its first 3 lines match --marker (default: FENCE|GUARD|CERCA,
# case-insensitive). A fence must contain a refutation record matching --record
# (default: refut|inject|Actual:) anywhere in the file. Files listed with --legacy are
# tolerated (declared debt, never silent), and the legacy list may only shrink: its
# size is printed so a gate can pin it. A file whose first 6 lines match --exclude declares
# itself a diagnostic (dump, probe, spike), not a guarantee, and is skipped (default: none).
# A project whose fences are not named like tests declares them by name with --sources (comma
# separated, relative to <dir>): each one counts as a fence whatever its name and whatever its
# first three lines say, and must carry its refutation record like any other. Without it the
# ledger is blind to a plugin whose guards are called `scope-lock`, not `scope_lock_test.sh`.
# A declared fence is held to a STRICTER record than the loose default: a dated line matching
# --source-record (default `[Rr]efuted <YYYY-MM-DD>`). The loose default would be satisfied by
# prose -- measured here: hooks/principles contains the word "Injects" in its description and
# passed the ledger without any refutation at all.
# Usage: refute-ledger.sh <test dir> [--marker <regex>] [--record <regex>] [--legacy <file>] [--exclude <regex>] [--sources <a,b,c>]
set -euo pipefail
dir="${1:?usage: refute-ledger.sh <test dir> [--marker re] [--record re] [--legacy file]}"; shift
marker='FENCE|GUARD|CERCA'; record='refut|inject|Actual:'; legacy=""; exclude=""; sources=""; source_record='[Rr]efuted [0-9]{4}-[0-9]{2}-[0-9]{2}'
while [ $# -gt 0 ]; do
  case "$1" in
    --marker) marker="$2"; shift 2 ;;
    --record) record="$2"; shift 2 ;;
    --legacy) legacy="$2"; shift 2 ;;
    --exclude) exclude="$2"; shift 2 ;;
    --sources) sources="$2"; shift 2 ;;
    --source-record) source_record="$2"; shift 2 ;;
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
# Fences the project declared by name. Counted even when the file is missing: a declared fence
# that does not exist is a hole in the declaration, not an absence of obligation.
if [ -n "$sources" ]; then
  IFS=',' read -r -a declared <<< "$sources"
  for name in "${declared[@]}"; do
    name="$(printf '%s' "$name" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [ -n "$name" ] || continue
    f="$dir/$name"
    if [ ! -f "$f" ]; then
      echo "  [FAIL] $f: declared with --sources and does not exist"; fail=$((fail + 1)); continue
    fi
    fences=$((fences + 1))
    if grep -q -E "$source_record" "$f"; then continue; fi
    if [ -n "$legacy" ] && grep -q -F -x "$f" "$legacy"; then tolerated=$((tolerated + 1)); continue; fi
    echo "  [FAIL] $f: declared as a fence and carries no dated refutation record ($source_record)"
    fail=$((fail + 1))
  done
fi
echo "refute-ledger: $fences fence(s), $tolerated legacy, $fail without a record"
[ "$fail" -eq 0 ]
