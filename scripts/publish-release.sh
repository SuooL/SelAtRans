#!/bin/bash
# Finalize a CI-verified tag locally: personal signing keys never leave Keychain.
set -euo pipefail
cd "$(dirname "$0")/.."
tag="${1:?Usage: scripts/publish-release.sh vX.Y.Z}"
version="$(cat VERSION)"
[[ "$tag" == "v$version" ]] || { echo 'Tag does not match VERSION.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Release checkout must be clean.' >&2; exit 1; }
git fetch origin main --tags
commit="$(git rev-parse "$tag^{commit}")"
[[ "$commit" == "$(git rev-parse origin/main)" && "$commit" == "$(git rev-parse HEAD)" ]] || {
    echo 'Check out the exact tagged, current main commit before publishing.' >&2; exit 1;
}
run_id="$(gh run list --repo SuooL/SelAtRans --workflow release.yml --commit "$commit" --json databaseId,status,conclusion --jq '[.[] | select(.status == "completed" and .conclusion == "success")][0].databaseId')"
[[ -n "$run_id" && "$run_id" != null ]] || { echo 'Wait for the tag Release workflow to succeed before local publication.' >&2; exit 1; }
staging="$(mktemp -d "${TMPDIR:-/tmp}/selatrans-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
gh run download "$run_id" --repo SuooL/SelAtRans --name SelAtRans-release-staging --dir "$staging/download"
ditto -x -k "$staging/download/SelAtRans.zip" "$staging/unpacked"
app="$staging/unpacked/SelAtRans.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$app/Contents/Info.plist")" == io.github.suool.SelAtRans ]]
lipo "$app/Contents/MacOS/SelAtRans" -verify_arch arm64 x86_64
REQUIRE_STABLE_SIGNING=1 scripts/sign-app.sh "$app"
mkdir -p dist "$staging/appcast" "$staging/dmg"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/SelAtRans.zip
ditto "$app" "$staging/dmg/SelAtRans.app"
ln -s /Applications "$staging/dmg/Applications"
hdiutil create -volname SelAtRans -srcfolder "$staging/dmg" -ov -format UDZO dist/SelAtRans.dmg >/dev/null
cp dist/SelAtRans.zip "$staging/appcast/"
.build/artifacts/sparkle/Sparkle/bin/generate_appcast \
    --account io.github.suool.SelAtRans.sparkle --maximum-deltas 0 \
    --download-url-prefix "https://github.com/SuooL/SelAtRans/releases/download/$tag/" \
    -o dist/appcast.xml "$staging/appcast"
python3 -B scripts/validate_appcast.py dist/appcast.xml
shasum -a 256 dist/SelAtRans.zip dist/SelAtRans.dmg > dist/SHA256SUMS
python3 -B scripts/version.py notes > "$staging/release-notes.md"
gh release create "$tag" --repo SuooL/SelAtRans --verify-tag --title "SelAtRans $tag" \
    --notes-file "$staging/release-notes.md" \
    dist/SelAtRans.zip dist/SelAtRans.dmg dist/SHA256SUMS dist/appcast.xml
