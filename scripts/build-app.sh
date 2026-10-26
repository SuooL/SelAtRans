#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${CONFIGURATION:-release}"
swift build --scratch-path .build -c "$configuration"
binary_dir="$(swift build --scratch-path .build -c "$configuration" --show-bin-path)"
output_dir="${APP_OUTPUT_DIR:-build/package}"
app="$output_dir/SelAtRans.app"
if [[ -f "$app/Contents/MacOS/SelAtRans" ]] && lsof -t "$app/Contents/MacOS/SelAtRans" >/dev/null 2>&1; then
    echo "Refusing to overwrite a running app. Quit it or set APP_OUTPUT_DIR to a separate directory." >&2
    exit 1
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
cp "$binary_dir/SelAtRans" "$app/Contents/MacOS/SelAtRans"
if [[ "${1:-}" == --universal ]]; then
    swift build --scratch-path .build -c "$configuration" --triple x86_64-apple-macosx13.0
    intel_dir="$(swift build --scratch-path .build -c "$configuration" --triple x86_64-apple-macosx13.0 --show-bin-path)"
    lipo -create "$binary_dir/SelAtRans" "$intel_dir/SelAtRans" -output "$app/Contents/MacOS/SelAtRans"
fi
framework=.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework
ditto "$framework" "$app/Contents/Frameworks/Sparkle.framework"
python3 - "$app" <<'PY'
import base64, plistlib, re
import sys
from pathlib import Path
version = Path('VERSION').read_text().strip()
assert re.fullmatch(r'\d+\.\d+\.\d+', version), 'VERSION must be MAJOR.MINOR.PATCH'
public = Path('packaging/sparkle-public-key.txt').read_text().strip()
assert len(base64.b64decode(public, validate=True)) == 32, 'Invalid Sparkle public key'
template = Path('packaging/Info.plist.in').read_text()
data = template.replace('__VERSION__', version).replace('__SPARKLE_PUBLIC_KEY__', public).encode()
plistlib.loads(data)
Path(sys.argv[1], 'Contents', 'Info.plist').write_bytes(data)
PY
swift scripts/make-icon.swift "$app"
scripts/sign-app.sh "$app"
plutil -lint "$app/Contents/Info.plist"
echo "Built $app"
