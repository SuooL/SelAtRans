#!/bin/bash
# Local signing uses a real, stable identity; CI-only artifacts may use ad-hoc signing.
set -euo pipefail
app="${1:?Usage: scripts/sign-app.sh APP_PATH}"
if [[ "${SIGNING_MODE:-}" == ci-adhoc || "${GITHUB_ACTIONS:-}" == true ]]; then
    if [[ "${REQUIRE_STABLE_SIGNING:-0}" == 1 ]]; then
        echo 'Public releases require local stable signing, not CI ad-hoc signing.' >&2
        exit 1
    fi
    codesign --force --sign - --timestamp=none "$app"
else
    identity="${SELATRANS_SIGNING_IDENTITY:-}"
    if [[ -z "$identity" ]]; then
        identity="$(python3 - <<'PY'
import re, subprocess, sys
result = subprocess.run(['security', 'find-identity', '-v', '-p', 'codesigning'], text=True, capture_output=True, check=True)
matches = [re.search(r'\b([A-F0-9]{40})\b', line)[1] for line in result.stdout.splitlines()
           if any(kind in line for kind in ('Apple Development:', 'Developer ID Application:', 'Mac Developer:'))]
if len(matches) != 1:
    sys.exit('Set SELATRANS_SIGNING_IDENTITY to the intended identity fingerprint when zero or multiple certificates exist.')
print(matches[0])
PY
)"
    fi
    codesign --force --sign "$identity" --timestamp=none "$app"
    # A cdhash-only designated requirement loses permissions every time the code changes.
    requirement="$(codesign -d -r- "$app" 2>&1)"
    if [[ "$requirement" == *'designated => cdhash'* ]]; then
        echo 'Stable code identity missing; refusing this signature.' >&2
        exit 1
    fi
fi
codesign --verify --deep --strict "$app"
