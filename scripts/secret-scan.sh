#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=8.30.1
case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) platform=darwin_arm64; checksum=b40ab0ae55c505963e365f271a8d3846efbc170aa17f2607f13df610a9aeb6a5 ;;
    Darwin-x86_64) platform=darwin_x64; checksum=dfe101a4db2255fc85120ac7f3d25e4342c3c20cf749f2c20a18081af1952709 ;;
    Linux-x86_64) platform=linux_x64; checksum=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb ;;
    Linux-aarch64) platform=linux_arm64; checksum=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080 ;;
    *) echo "Unsupported secret-scanner platform." >&2; exit 1 ;;
esac
scanner_dir="$(mktemp -d "${TMPDIR:-/tmp}/selatrans-scan.XXXXXX")"
trap 'rm -rf "$scanner_dir"' EXIT
archive="gitleaks_${version}_${platform}.tar.gz"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
    "https://github.com/gitleaks/gitleaks/releases/download/v${version}/${archive}" \
    --output "$scanner_dir/$archive"
printf '%s  %s\n' "$checksum" "$scanner_dir/$archive" | shasum -a 256 --check --status
tar -xzf "$scanner_dir/$archive" -C "$scanner_dir" gitleaks
"$scanner_dir/gitleaks" dir . --config .gitleaks.toml --redact --no-banner
if [[ "${1:-}" == --history ]]; then
    "$scanner_dir/gitleaks" git . --config .gitleaks.toml --redact --no-banner --log-opts=--all
fi
