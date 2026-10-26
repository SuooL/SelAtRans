#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$#" != 3 ]]; then
    echo "Usage: scripts/pr.sh BASE TITLE BODY_FILE" >&2
    exit 1
fi
body_file="$(mktemp "${TMPDIR:-/tmp}/selatrans-pr.XXXXXX")"
trap 'rm -f "$body_file"' EXIT
python3 -B scripts/agent_attribution.py body "$3" > "$body_file"
gh pr create --base "$1" --title "$2" --body-file "$body_file"
