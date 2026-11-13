#!/usr/bin/env bash
# front-roots
# Run alone: bash tests/scripts/front-roots.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── one rule for "the repository a file belongs to", in two languages ───────────────────────
# The fences ask the shell (`rw_target_root`, hooks/lib.sh) which repository a target is in. From
# 0.8.0 the script that opens a front asks the same question in Python (`repo_of`,
# hooks/planblocks.py), to decide in which repository each line of a plan's Scope opens a front.
# Two answers to one question is how a front opens in a repository the fences then judge by
# another: this table is handed to both, and they have to agree on every row.
section "front-roots (the two resolvers of a file's repository agree)"
W="$TMP/world"; mkdir -p "$W"; W="$(cd "$W" && pwd -P)"
fx_repo "$W/plain"; mkdir -p "$W/plain/src/deep"
fx_repo "$W/mono"; mkdir -p "$W/mono/.roadworthy" "$W/mono/docs"
fx_repo "$W/mono/app"; mkdir -p "$W/mono/app/.roadworthy" "$W/mono/app/lib"      # nested, with a rite of its own
fx_repo "$W/mono/vendored"; mkdir -p "$W/mono/vendored/pkg"                       # nested, with none
fx_repo "$W/mono/vendored/inner"                                                  # nested twice, with none
fx_repo "$W/bare-outer"; fx_repo "$W/bare-outer/bare-inner"                       # nested, and nobody above has one
mkdir -p "$W/no-repo/dir"
ln -s "$W/plain" "$W/link-to-plain"
shell_root() { bash -c 'export RW_ON_CRASH=allow; source "$1/hooks/lib.sh"; trap - ERR EXIT; rw_target_root "$2"' _ "$ROOT" "$1" 2>/dev/null; }
python_root() { python3 "$ROOT/hooks/planblocks.py" root "$1"; }
rows=0
while IFS= read -r path; do
  [ -n "$path" ] || continue
  rows=$((rows + 1))
  s="$(shell_root "$path")"; p="$(python_root "$path")"
  [ "$s" = "$p" ] || fail "the two resolvers of a file's repository disagree on ${path#"$W"/}: the shell says '${s#"$W"/}', python says '${p#"$W"/}'"
done <<ROWS
$W/plain/src/deep/a.py
$W/plain/src/not/there/yet.py
$W/plain
$W/mono/docs/x.md
$W/mono/app/lib/main.dart
$W/mono/app
$W/mono/vendored/pkg/x.c
$W/mono/vendored/inner/y.c
$W/bare-outer/bare-inner/z
$W/bare-outer/f
$W/no-repo/dir/file
$W/link-to-plain/src/a.py
/nonexistent-top/dir/file
ROWS
[ "$rows" -eq 13 ] && ok "$rows paths, and the shell and python name the same repository for each" || fail "the table of paths was not walked whole ($rows rows)"
# The rows mean what they say: the answers themselves, for the three that carry the rule.
[ "$(python_root "$W/mono/vendored/inner/y.c")" = "$W/mono" ] \
  && ok "a repository nested twice with no rite of its own answers to the nearest one above that has one" || fail "the two resolvers of a file's repository disagree with the rule: nested twice -> $(python_root "$W/mono/vendored/inner/y.c")"
[ "$(python_root "$W/mono/app/lib/main.dart")" = "$W/mono/app" ] \
  && ok "a nested repository with a rite of its own is its own" || fail "the two resolvers of a file's repository disagree with the rule: nested with a rite -> $(python_root "$W/mono/app/lib/main.dart")"
[ "$(python_root "$W/bare-outer/bare-inner/z")" = "$W/bare-outer/bare-inner" ] \
  && ok "and with no rite anywhere above, a nested repository is its own" || fail "the two resolvers of a file's repository disagree with the rule: no rite above -> $(python_root "$W/bare-outer/bare-inner/z")"
[ -z "$(python_root "$W/no-repo/dir/file")" ] && ok "a path in no repository has none" || fail "a path in no repository was given one"

rw_end
