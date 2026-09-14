#!/usr/bin/env bash
# What the harness writes and the plugin reads: a project's memory directory and a session
# transcript. Both are evidence the plugin does not author, which is the whole reason it trusts
# them -- and the reason forging one is a DECLARED limit in tests/attack.sh.

# fx_memory_project <dir> — a Claude Code project directory with a numbered MEMORY.md.
fx_memory_project() {
  mkdir -p "$1/memory"
  printf '# index\n1. Project rule one → [detail](feedback_one.md)\n- not a rule\n2. Project rule two\n' > "$1/memory/MEMORY.md"
  : > "$1/memory/feedback_one.md"
}

# fx_transcript <file> <command...> — a transcript in the harness's own shape, one Bash tool_use
# per command given.
fx_transcript() {
  local out="$1"; shift
  : > "$out"
  local c
  for c in "$@"; do
    python3 -c 'import json,sys; print(json.dumps({"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":sys.argv[1]}}]}}))' "$c" >> "$out"
  done
}
