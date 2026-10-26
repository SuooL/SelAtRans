#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/build-app.sh --universal
mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent build/package/SelAtRans.app dist/SelAtRans.zip
staging="$(mktemp -d "${TMPDIR:-/tmp}/selatrans-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto build/package/SelAtRans.app "$staging/SelAtRans.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname SelAtRans -srcfolder "$staging" -ov -format UDZO dist/SelAtRans.dmg >/dev/null
shasum -a 256 dist/SelAtRans.zip dist/SelAtRans.dmg > dist/SHA256SUMS
