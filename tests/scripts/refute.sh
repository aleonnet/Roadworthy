#!/usr/bin/env bash
# refute
# Run alone: bash tests/scripts/refute.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "refute.sh"
T="$TMP/toy"; mkdir -p "$T"; printf 'answer=42\n' > "$T/config.txt"
cat > "$T/check.sh" <<'EOF'
#!/usr/bin/env bash
grep -q '^answer=42$' "$(dirname "$0")/config.txt" || { echo "config: answer is not 42"; exit 1; }
EOF
chmod +x "$T/check.sh"
before="$(shasum -a 256 "$T/config.txt" | cut -d' ' -f1)"
bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'answer is not 42' -- "$T/check.sh" >/dev/null \
  && ok "check goes red for the intended reason; file restored" || fail "refute happy path"
[ "$(shasum -a 256 "$T/config.txt" | cut -d' ' -f1)" = "$before" ] && ok "hash identical after restore" || fail "hash differs after restore"
# The record is written by the script, not by whoever reports the result. A refutation that exists
# only as a sentence in a report is precisely what this tool replaces.
RLED="$TMP/rwdata-refute/refutations.jsonl"
ROADWORTHY_DATA="$TMP/rwdata-refute" bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'answer is not 42' -- "$T/check.sh" >/dev/null
[ -f "$RLED" ] && python3 -c 'import json,sys
r = json.loads(open(sys.argv[1]).read().strip().splitlines()[-1])
need = {"ts","file","sha_before","sha_after","restored","injection","expect","exit_red","exit_clean","check_cmd","head"}
missing = need - set(r)
sys.exit(0 if not missing and r["restored"] and r["exit_red"] != 0 and r["exit_clean"] == 0 else 1)' "$RLED" \
  && ok "refute.sh records the refutation itself, with both hashes and both exit codes" || fail "no usable refutation record"
printf '#!/usr/bin/env bash\nexit 0\n' > "$T/green.sh"; chmod +x "$T/green.sh"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'x' -- "$T/green.sh" >/dev/null 2>&1 \
  && ok "a check that stays green is reported as a failed refutation" || fail "green check accepted"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'some other reason' -- "$T/check.sh" >/dev/null 2>&1 \
  && ok "red for the wrong reason is rejected" || fail "wrong reason accepted"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/nomatch/x/' --expect 'x' -- "$T/check.sh" >/dev/null 2>&1 \
  && ok "injection that changes nothing is rejected" || fail "no-op injection accepted"
printf '#!/usr/bin/env bash\necho "always red"; exit 1\n' > "$T/red.sh"; chmod +x "$T/red.sh"
! bash skills/refute/scripts/refute.sh --file "$T/config.txt" --sed 's/42/43/' --expect 'always red' -- "$T/red.sh" >/dev/null 2>&1 \
  && ok "red on the clean file too is rejected (no green-on-clean)" || fail "always-red check accepted"

rw_end
