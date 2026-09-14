#!/usr/bin/env bash
# globmatch
# Run alone: bash tests/scripts/globmatch.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── one glob grammar, three consumers, one table ────────────────────────────
# Until 0.6.1 the scope lock, the closing and the eval instrument each carried their own matcher.
# rw-metrics answered through fnmatch first, where `*` crosses a `/`: `app/*.py` meant one thing to
# the lock that denied the edit and another to the instrument that counted it out of scope. Every
# row below is put to the three entry points, and each has to give the answer in the last column.
section "globmatch (one grammar for lib.sh, close.sh and rw-metrics)"
lib_match() {  # <path> <globs> → 1|0
  RW_HOOK=x RW_ON_CRASH=deny bash -c 'source hooks/lib.sh; if rw_glob_match "$1" "$2"; then echo 1; else echo 0; fi' _ "$1" "$2"
}
cli_match() {  # the module close.sh imports, through its command-line door
  if python3 hooks/globmatch.py "$1" "$2"; then echo 1; else echo 0; fi
}
metrics_match() {  # the function rw-metrics calls, loaded from the script itself
  python3 - "$1" "$2" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("rwm", "bin/rw-metrics")
spec = importlib.util.spec_from_loader("rwm", loader)
m = importlib.util.module_from_spec(spec); loader.exec_module(m)
print(1 if m.glob_match(sys.argv[1], sys.argv[2].split(",")) else 0)
PY
}
# path | globs | expected
TABLE='README.md|README.md|1
docs/README.md|README.md|0
docs/README.md|**/README.md|1
app/x.py|app/*.py|1
app/sub/x.py|app/*.py|0
app/sub/x.py|app/**|1
app|app/**|0
x.py|?.py|1
xy.py|?.py|0
./a.py|a.py|1
a.py|# comment,a.py|1
lib/ble/manager.dart|lib/ble/**,**/permissions.dart|1
a/b/permissions.dart|lib/ble/**,**/permissions.dart|1
lib/ui/home.dart|lib/ble/**,**/permissions.dart|0'
rows=0; bad=0
while IFS='|' read -r path globs want; do
  [ -n "$path" ] || continue
  rows=$((rows + 1))
  a="$(lib_match "$path" "$globs")"; b="$(cli_match "$path" "$globs")"; c="$(metrics_match "$path" "$globs")"
  if [ "$a" = "$want" ] && [ "$b" = "$want" ] && [ "$c" = "$want" ]; then :; else
    bad=$((bad + 1)); printf '          %s vs %s: lib.sh=%s globmatch.py=%s rw-metrics=%s expected=%s\n' "$path" "$globs" "$a" "$b" "$c" "$want" >&2
  fi
done <<< "$TABLE"
[ "$bad" -eq 0 ] && ok "the three matchers agree with the table on $rows rows" || fail "the three matchers disagree on $bad of $rows rows"
# And the closing reads the same module: a second copy of the grammar inside close.sh is how the
# three drifted apart in the first place.
grep -q 'from globmatch import' skills/close/scripts/close.sh && ! grep -q 'def to_regex' skills/close/scripts/close.sh \
  && ok "close.sh imports the module and carries no grammar of its own" || fail "close.sh still carries its own glob grammar"
grep -q 'from globmatch import' bin/rw-metrics && ! grep -q -E 'import fnmatch|fnmatch\.fnmatch' bin/rw-metrics \
  && ok "rw-metrics imports the module and no longer answers through fnmatch" || fail "rw-metrics still has its own matcher"

rw_end
