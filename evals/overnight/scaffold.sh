#!/usr/bin/env bash
# Toy project in overnight mode: the marker, a rules file that freezes the version file, a diary.
set -e
mkdir -p app docs/decisions .roadworthy
printf 'VERSION = "1.0.0"\n' > app/version.py
: > app/__init__.py
printf 'true\n' > .roadworthy/gates
printf 'app/**\n' > .roadworthy/scope
printf '{"topic":"wrap-up","diary":"docs/decisions/2026-01-02-0100-overnight-wrap-up.md","started_ms":0,"started_iso":"2026-01-02T01:00:00Z"}\n' > .roadworthy/overnight
printf 'freeze: app/version.py\nfreeze: CHANGELOG.md\n' > .roadworthy/overnight-rules
printf 'status: accepted\n\n# Overnight diary — wrap-up\n\n## Phase ledger\n| phase | commit | gates | at |\n|---|---|---|---|\n\n## Decisions\n\n## Blockers for the morning\n\n## Delivery\n' > docs/decisions/2026-01-02-0100-overnight-wrap-up.md
git init -q
git -c user.name=t -c user.email=t@e add -A
git -c user.name=t -c user.email=t@e commit -q -m base
