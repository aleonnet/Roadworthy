#!/usr/bin/env bash
# The quality gate for Roadworthy itself. Local and CI run exactly this.
#
# Every hook is exercised with real stdin JSON, in both directions: it must deny what it claims to
# deny and pass what it claims to pass. Every script is refuted once. The manifest is validated
# with the official CLI when present. What changed in 0.6.1 is only WHERE that lives: one case per
# fence in tests/hooks/, one per script in tests/scripts/, the shared half in tests/lib.sh, and the
# toy repositories in tests/fixtures/ instead of a heredoc in the middle of an assertion.
#
# Run one case alone -- which is the point of the split, and what makes a refutation cost one file
# instead of two full suite runs:
#
#     bash tests/hooks/scope-lock.sh
#
# THE MANIFEST IS THE FENCE. A runner that globs a directory loses a case in silence the day
# someone deletes the file, and a suite that quietly stops measuring something is the exact defect
# this plugin exists to prevent. tests/cases.txt lists every case; this script refuses to run when
# the list and the directory disagree, in either direction.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/.."
cd "$ROOT" || { echo "tests/run.sh: cannot enter $ROOT" >&2; exit 1; }

MANIFEST="${RW_MANIFEST:-tests/cases.txt}"
[ -f "$MANIFEST" ] || { echo "tests/run.sh: $MANIFEST is missing; it is what says which cases exist." >&2; exit 1; }
declared="$(grep -v -E '^[[:space:]]*(#|$)' "$MANIFEST" | sort)"
ondisk="$(cd tests && ls meta/*.sh hooks/*.sh scripts/*.sh 2>/dev/null | sed 's|^|tests/|' | sort)"
if [ "$declared" != "$ondisk" ]; then
  echo "tests/run.sh: the case manifest and the case files disagree." >&2
  echo "  only in $MANIFEST:" >&2; comm -23 <(printf '%s\n' "$declared") <(printf '%s\n' "$ondisk") | sed 's/^/    /' >&2
  echo "  only on disk:" >&2;      comm -13 <(printf '%s\n' "$declared") <(printf '%s\n' "$ondisk") | sed 's/^/    /' >&2
  echo "  A case that is on disk and not declared never runs; one declared and absent is a case someone deleted." >&2
  exit 1
fi
# --check-manifest runs ONLY the comparison above and leaves, so tests/meta/runner.sh can measure
# that guarantee without running the suite inside the suite. Written after doing exactly that by
# accident: the flag had not landed, the self-test called the runner, the runner ran the self-test,
# and the machine went to work on an exponential number of suites.
[ "${1:-}" = --check-manifest ] && { echo "tests/run.sh: the manifest and the case files agree"; exit 0; }

# Cases are independent by construction -- each builds its own fixtures under its own mktemp --
# so they run in parallel and their output is buffered and printed in manifest order. Measured
# 2026-09-14 on this machine: 235 s serial, 183 s at four jobs, 251 s at eight -- past four it
# oversubscribes and gets SLOWER, because every assertion already spawns a bash and a python.
# The two slowest cases (plan-review-gate 51 s, rite-gate 38 s) are the floor. RW_JOBS=1 puts
# it back in order for a bisect.
JOBS="${RW_JOBS:-4}"
FAILED=0; RAN=0
CASES=()
while IFS= read -r line; do [ -n "$line" ] && CASES+=("$line"); done < <(grep -v -E '^[[:space:]]*(#|$)' "$MANIFEST")
OUTDIR="$(mktemp -d)"; trap 'rm -rf "$OUTDIR"' EXIT
i=0
for case in "${CASES[@]}"; do
  bash "$case" > "$OUTDIR/$i.out" 2> "$OUTDIR/$i.err"; echo $? > "$OUTDIR/$i.rc" &
  i=$((i + 1))
  # `wait -n` is bash 4.3+; the bash that ships with macOS is 3.2.57, where it does not exist
  # and the throttle it was written with degenerated into no throttle at all. Polling is the
  # portable form, and a broken limiter with a confident comment above it is worse than none.
  while [ "$(jobs -pr | wc -l)" -ge "$JOBS" ]; do sleep 0.2; done
done
wait
i=0
for case in "${CASES[@]}"; do
  RAN=$((RAN + 1))
  cat "$OUTDIR/$i.out"
  if [ "$(cat "$OUTDIR/$i.rc" 2>/dev/null || echo 1)" != 0 ]; then
    printf '  [CASE RED] %s\n' "$case" >&2
    sed 's/^/      /' "$OUTDIR/$i.err" >&2
    FAILED=$((FAILED + 1))
  fi
  i=$((i + 1))
done

# ── the cheating suite ───────────────────────────────────────────────────────
# Not a case: it asks a different question. tests/* ask each fence whether it does what it says;
# tests/attack.sh tries to get PAST it, and reports what passes as a DECLARED limit.
printf '\n== attack.sh (the cheating suite)\n'
if out="$(bash "$ROOT/tests/attack.sh" 2>&1)"; then
  printf '  [OK]   %s\n' "$(printf '%s' "$out" | tail -1)"
else
  printf '  [FAIL] an attack got through undeclared\n' >&2
  printf '%s\n' "$out" | sed 's/^/      /' >&2
  FAILED=$((FAILED + 1))
fi

printf '\n%d case(s) run\n' "$RAN"
if [ "$FAILED" -eq 0 ]; then echo "RESULT: gate clean"; else echo "RESULT: $FAILED case(s) red"; exit 1; fi
