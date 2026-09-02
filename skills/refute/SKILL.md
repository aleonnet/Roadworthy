---
name: refute
description: Prove that a test, fence or guard actually fails when the defect it claims to catch is present. Use before declaring any new test, hook or check "done", when a suite has been green suspiciously long, or when the user asks to verify a guarantee.
argument-hint: [test command] [file to mutate]
allowed-tools: Bash Read Grep Glob
---

# Refute

A guarantee counts only after it has been refuted once. Refutation means: put the defect
back on purpose, watch the check go red **for the intended reason**, restore the file byte
for byte, and prove the restore with a hash.

## Procedure

1. **Name the claim.** One sentence: "`<check>` fails when `<defect>`." If you cannot phrase
   the defect, the check has no claim to refute.
2. **Snapshot.** `sha256` of every file you will touch, kept in a temporary directory outside
   the repository. Never rely on `git checkout --` to restore: it restores the index, not the
   bytes you had.
3. **Inject exactly the defect** from step 1, nothing else. A broken build or a syntax error
   is not a refutation; the check must fail on its own assertion.
4. **Run the check** and read the failure text. The failure must name the injected defect.
   Record the command and the relevant lines of output.
5. **Restore** from the snapshot and verify the hash matches. Only then continue.
6. **Write it down** in the check's header: what was injected, what the check said.

`scripts/refute.sh` performs steps 2, 4 and 5 mechanically:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/refute/scripts/refute.sh" \
  --file path/to/production_file --sed 's/return 8;/return 9;/' \
  --expect 'header 9 x expected 8' -- bash test/run.sh
```

It exits 0 only when the check failed with the expected text **and** the file was restored
with an identical hash. Any other outcome exits 1 and prints why.

## What refutation is not

- It is not mutation testing. Mutation testing scores a suite statistically; refutation
  targets one claim. Use both: refutation for every new check, a mutation score for the
  class of "green forever" tests.
- It is not a review. The cold reviewer reads; refutation executes.
