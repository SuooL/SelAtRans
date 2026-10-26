#!/bin/bash
# Canonical local pre-commit/pre-PR gate. Do not commit or open a PR until it passes.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/check.sh
scripts/secret-scan.sh --history
echo 'Local CI test passed. Commit and PR creation may proceed.'
