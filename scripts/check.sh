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
swift build --scratch-path .build --product CoreChecks -j 2
checks_dir="$(swift build --scratch-path .build --show-bin-path)"
# Explicitly seal the standalone check executable before running on hosted macOS.
codesign --force --sign - --timestamp=none "$checks_dir/CoreChecks"
codesign --verify --strict "$checks_dir/CoreChecks"
"$checks_dir/CoreChecks"
scripts/build-app.sh
if [[ "${GITHUB_ACTIONS:-}" != true && "${SIGNING_MODE:-}" != ci-adhoc ]]; then
    python3 -B scripts/verify-signing.py
fi
echo "Repository checks passed."
