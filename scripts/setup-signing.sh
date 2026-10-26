#!/bin/bash
# One-time maintainer setup. Private update key stays in Keychain.
set -euo pipefail
umask 077
cd "$(dirname "$0")/.."
tool=.build/artifacts/sparkle/Sparkle/bin/generate_keys
if [[ ! -x "$tool" ]]; then
    echo 'Run swift build first to fetch checksum-verified Sparkle tools.' >&2
    exit 1
fi
account=io.github.suool.SelAtRans.sparkle
"$tool" --account "$account"
mkdir -p packaging
"$tool" --account "$account" -p > packaging/sparkle-public-key.txt
echo 'Signing configured. Only the public key file belongs in Git.'
