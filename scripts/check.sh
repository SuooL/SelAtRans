#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git diff --check
git diff --cached --check
for script in scripts/*.sh .githooks/*; do
    bash -n "$script"
done
python3 -B -m unittest discover -s scripts/tests -v
python3 -B scripts/version.py check
swift run --scratch-path .build CoreChecks
scripts/build-app.sh
if [[ "${GITHUB_ACTIONS:-}" != true && "${SIGNING_MODE:-}" != ci-adhoc ]]; then
    python3 -B scripts/verify-signing.py
fi
echo "Repository checks passed."
