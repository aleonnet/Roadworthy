#!/usr/bin/env bash
# tree-fingerprint
# Run alone: bash tests/scripts/tree-fingerprint.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/lib.sh"

# ── tree-fingerprint ─────────────────────────────────────────────────────────
section "tree-fingerprint.sh"
G="$TMP/fp-repo"; fx_repo_committed "$G"
fp1="$(bash skills/close/scripts/tree-fingerprint.sh "$G")"
echo y > "$G/f"
fp2="$(bash skills/close/scripts/tree-fingerprint.sh "$G")"
[ "$fp1" != "$fp2" ] && ok "fingerprint changes with the tree" || fail "fingerprint unchanged"
printf '%s' "$fp2" | grep -q ' dirty$' && ok "dirty tree reported" || fail "dirty not reported"

# ── tree-fingerprint: content, not commits ──────────────────────────────────
section "tree-fingerprint.sh (content)"
CF="$TMP/fp-content"; fx_docs_tree_committed "$CF"
read -r _ t1 _ <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
git -C "$CF" commit -q --allow-empty -m "no content change"
read -r _ t2 _ <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
[ "$t1" = "$t2" ] && ok "new commit with identical content keeps the fingerprint" || fail "fingerprint changed without content change"
echo x >> "$CF/docs/README.md"
read -r _ t3 s3 <<< "$(bash skills/close/scripts/tree-fingerprint.sh "$CF")"
[ "$t1" != "$t3" ] && [ "$s3" = "dirty" ] && ok "one byte changes it and the tree is dirty" || fail "content change not detected"
git -C "$CF" checkout -q -- docs/README.md

rw_end
