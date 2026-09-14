#!/usr/bin/env bash
# rw-metrics
# Run alone: bash tests/scripts/rw-metrics.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── plan template: risk band ────────────────────────────────────────────────
# ── rw-metrics: KPIs from a synthetic run ───────────────────────────────────
section "rw-metrics"
if python3 -m pytest --version >/dev/null 2>&1; then
  RM="$TMP/rm"; mkdir -p "$RM/run/out" "$RM/run/sealed/home/cwd"
  W="$RM/run/sealed/home/cwd"
  (cd "$W" && git init -q && mkdir -p app tests && printf 'def f():\n    return 1\n' > app/a.py && : > app/__init__.py \
    && printf 'from app.a import f\n\ndef test_f():\n    assert f() == 2\n' > tests/test_a.py \
    && printf 'def test_ok():\n    assert True\n' > tests/test_b.py \
    && printf 'app/a.py\n' > SCOPE.txt && printf 'tests/test_a.py::test_f\n' > TARGET_TESTS.txt \
    && git -c user.name=t -c user.email=t@e add -A && git -c user.name=t -c user.email=t@e commit -q -m base \
    && printf 'def f():\n    return 2\n' > app/a.py && printf 'def test_ok():\n    assert False\n' > tests/test_b.py && printf 'x\n' > stray.txt)
  printf '%s\n' '{"type":"result","num_turns":4,"duration_ms":9000,"result":"done\nSTATUS: passed","permission_denials":[{"tool_name":"Edit"}],"modelUsage":{"m":{"inputTokens":100,"outputTokens":50,"cacheReadInputTokens":7}}}' > "$RM/run/out/trace.jsonl"
  printf '{"cases":[{"name":"c","arms":{"with":[{"score":1,"costUsd":0.1,"turns":4,"durationSeconds":9,"tracePath":"%s"}]}}]}' "$RM/run/out/trace.jsonl" > "$RM/r.json"
  out="$(python3 bin/rw-metrics t="$RM/r.json" 2>&1)"
  echo "$out" | grep -q '| t | c | with | 1 | 1.0 | 1/1 | 1 | 2 | 1 | 1 | 1 | 150.0 | 7.0 | 4.0 | 9.0 | 0.1 |' && ok "K1 pass, K2 one regression, K3 two files out of scope, K4 false success, K5 one denial, K6/K7 from the trace" || { fail "rw-metrics table differs"; echo "$out" | head -5; }
else
  echo "  [SKIP] pytest not installed"
fi

rw_end
