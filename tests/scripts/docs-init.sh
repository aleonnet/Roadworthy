#!/usr/bin/env bash
# docs-init
# Run alone: bash tests/scripts/docs-init.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

section "docs-init.sh"
DI="$TMP/di"; mkdir -p "$DI"
bash skills/document/scripts/docs-init.sh "$DI" > "$TMP/di1.log" && ok "first run creates the tree" || fail "docs-init first run"
grep -q 'created  docs/decisions/' "$TMP/di1.log" && [ -f "$DI/docs/README.md" ] && [ -f "$DI/docs/plans/done/README.md" ] && ok "map, roles and done index created" || fail "tree incomplete"
# The generated docs.json carries the status dictionary, EMPTY and uncommented: docs-check.sh and
# plan-review-gate read it with json.load, and one "//" would break the documentation gate of
# every new project. A project that never declares a word keeps English, which is the default.
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("status")=={} else 1)' "$DI/.roadworthy/docs.json" \
  && ok "the generated docs.json has an empty status dictionary and parses as JSON" || fail "generated docs.json has no usable status key"
snap="$(cd "$DI" && find . -type f -exec shasum -a 256 {} + | sort)"
bash skills/document/scripts/docs-init.sh "$DI" > "$TMP/di2.log"
[ "$snap" = "$(cd "$DI" && find . -type f -exec shasum -a 256 {} + | sort)" ] && ! grep -q 'created' "$TMP/di2.log" && ok "second run changes nothing and reports 'exists'" || fail "docs-init not idempotent"

rw_end
