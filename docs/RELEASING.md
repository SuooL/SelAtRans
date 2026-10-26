# Version and release management

This follows OmniStats' Sparkle + GitHub Release approach, using separate
SelAtRans update keys and a stable local Apple signing identity. `VERSION` is the
single version source; packaging derives both bundle version fields from it.
Tags are `vMAJOR.MINOR.PATCH`.

## Normal release

1. Start `chore/release-X.Y.Z` from current `origin/dev`. Add a release section
   to `CHANGELOG.md`, then run `python3 scripts/version.py bump X.Y.Z`.
2. Run the complete local gate, open a PR into `dev`, and enable squash auto-merge.
   Wait for required CI and remote merged state.
3. Create a `dev` → `main` PR with `scripts/pr.sh`; enable merge-commit auto-merge
   (`gh pr merge --auto --merge`). Never squash the release PR.
4. After merge and CI, tag the exact remote main commit and push the tag. Release
   CI rejects a tag that differs from VERSION or current main.
5. The tag workflow repeats validation and secret scans, builds arm64 + x86_64,
   and uploads a staging artifact. It has no signing credentials and cannot
   publish an ad-hoc-signed application as a stable release.
6. On the maintainer Mac, check out the exact tagged main commit, then run
   `scripts/publish-release.sh vX.Y.Z`. It requires successful tag CI, downloads
   that run's staging artifact, verifies bundle ID/version/architectures, signs
   with the local Apple identity, packages ZIP/DMG, generates a signed appcast
   using Keychain, checks metadata, and publishes ZIP, DMG, SHA256SUMS, appcast.xml.
7. Verify the remote release and assets. Test an actual older → newer Sparkle
   installation before claiming download/install/relaunch was validated.

The final signing/publication step runs locally to keep the existing personal
Apple certificate private key off GitHub. No certificate export, CI signing
secret, or self-hosted runner is required. A future cloud-signing implementation
requires separate explicit authorization to export that personal identity.

`main` and default `dev` stay protected. Merged temporary branches are removed.
Releases are immutable: fix a published version with a higher patch version.

## Stable identity and permissions

`scripts/sign-app.sh` uses the sole valid Apple Development / Developer ID / Mac
Developer identity in local Keychain. If multiple identities exist, explicitly
set `SELATRANS_SIGNING_IDENTITY` to the intended fingerprint. The selection is
local configuration and is not committed. No ad-hoc fallback is permitted for a
local release. `scripts/verify-signing.py` checks that changed bundle content has
the same certificate-backed designated requirement.

Keep the bundle identifier, signer/team, and normal install location stable.
The one-time move from an ad-hoc build to the certificate-signed build may require
renewed Accessibility/Keychain approval. Ordinary subsequent updates should
satisfy the same code identity; OS resets, certificate revocation, or changing
signer can still require new approval. Never replace the requirement with a
bundle-identifier-only expression or disable system security checks.

The existing free Personal Team Apple Development identity is used for this
maintainer's Mac. It is not a Developer ID distribution/notarization certificate.
Apple notarization and Developer ID signing are not configured; do not claim
Gatekeeper approval or unrestricted distribution entitlement. Certificate expiry
and renewal must be checked as part of ongoing maintenance.

CI's `GITHUB_ACTIONS=true` selects ad-hoc signing only for staging artifacts.
Build outputs go to `build/package`, separate from an installed app; a build
refuses to overwrite a running output bundle. `APP_OUTPUT_DIR` can select another
staging directory. Do not run a previous staging build while repackaging it.

## Sparkle update signing

Sparkle 2.9.5 is exact-version pinned in SwiftPM; SwiftPM verifies its artifact
checksum. Framework signatures and symlinks are preserved with `ditto`.

Run `scripts/setup-signing.sh` once after `swift build`. It creates a project-
specific Ed25519 update key in Keychain and writes only its public key to
`packaging/sparkle-public-key.txt`. Do not overwrite it: installed versions must
trust later updates. Do not reuse OmniStats' key. Private update and Apple signing
keys both remain in Keychain; Git and CI need neither private key.

The latest release's static appcast avoids GitHub REST polling. Scheduled checks
run once per day by default and can be disabled. Automatic downloads and silent
installation are disabled. The source text and LLM credentials are unrelated to
and never used by the update mechanism.

References: [Apple code identity and permissions](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements),
[Apple certificate roles](https://developer.apple.com/help/account/certificates/certificates-overview/),
[Sparkle publishing](https://sparkle-project.org/documentation/publishing/).
