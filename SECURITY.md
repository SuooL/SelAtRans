# Security

Do not open public issues containing credentials, private text, patient data,
API request/response bodies, or personal settings.

SelAtRans stores API keys as plaintext files in
`~/Library/Application Support/SelAtRans/Credentials`, scoped to profile and
endpoint origin. The app enforces mode 0700 on the credential directory and mode
0600 on regular, current-user-owned credential files, rejects symlinks and hard
links on reads, and saves atomically without a world-readable intermediate file.
This avoids Keychain password prompts but does not provide encryption at rest;
other processes running as the same user can access these files. Keep them out
of shared directories and Git. App API credentials never use Keychain; legacy
items are left untouched, so upgrades require one-time key re-entry.
Ordinary preferences contain only non-secret options. User text is held in memory
and sent only to the configured HTTPS provider after a deliberate shortcut.
The provider's own retention and processing policies apply to that request.
The latest streamed result is retained only in memory for the preview, with a
bounded output size; no translation history is persisted.

This public repository does not need API credentials in GitHub Actions. All CI
API tests use a fake in-memory transport and synthetic input.
Apple signing and Sparkle update private keys remain in the maintainer's local
Keychain. CI produces staging artifacts; local signing precedes publication.

Local hooks and CI run Gitleaks with redaction. Repository owners should also
keep GitHub secret scanning and push protection enabled when available. Detection
is defense in depth and cannot guarantee discovery of every possible secret.

Report a security vulnerability through GitHub private vulnerability reporting
when available; do not publish exploit details or actual secrets in an issue.
