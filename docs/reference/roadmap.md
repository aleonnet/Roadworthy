# Roadmap

Living document (undated name by design). One line per item, with the measured reason.

## Done
- 0.1 hooks and skills; 0.2 documentation tree by role, evidence-gated close, refutation
  ledger, resume by name; 0.2.1 per-project status vocabulary (found by adopting on a
  Portuguese-language monorepo).
- Evals suite (`evals/`, six cases) and `bin/rw-metrics` (seven KPIs from the eval JSON, the
  run trace and the kept workspace).

## Pending
- **Bash-granting evals on macOS with Docker Desktop.** `claude plugin eval --allow-tools Bash`
  refuses to run when the Docker credential store contains symbolic links (Docker Desktop
  keeps its CLI plugins as links under `~/.docker/cli-plugins`); `DOCKER_CONFIG` does not
  bypass the check because both locations are inspected. Consequence: the `commit` (forbidden
  flag, empty staging) and `refute` cases cannot run locally; both guards are covered by the
  unit gate (`tests/run.sh`), not by the experiment. Plan: run those two cases in CI on a
  Linux runner, where the store is a plain directory.
- `hooks/stop-gate` (Stop): block the turn while `close.sh --check` reports STALE or MISSING
  gates; opt-in (`stop_gate`), fails open.
- `/mutate` with `scripts/mutate-baseline.sh`: read the report of the language's mutation
  tool and print the measured score as the suggested threshold.
- Denials log: `deny()` appends `{ts, hook, reason, cwd}` to `denials.jsonl` so the
  guardrail count is readable without the eval trace.
- **Scope widening made visible.** The scope lock lets the agent edit `.roadworthy/scope`
  by design; in the with-and-without experiment (2026-09-02) one run crossed the scope that way
  after three denials. Record widenings (`{ts, before, after, cwd}` in `denials.jsonl` or a
  sibling ledger) so `close.sh --check` and `rw-metrics` print "scope widened during the task".
- Prune graders that pass in both arms once three runs with the target model are in hand
  (agentskills.io guidance: such assertions inflate the with-plugin pass rate).
