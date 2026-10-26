#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
git diff --check
git diff --cached --check
for script in scripts/*.sh .githooks/*; do
    bash -n "$script"
done
python3 -B -m unittest discover -s scripts/tests -v
echo "Repository checks passed."
