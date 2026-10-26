# Security

Do not open public issues containing credentials, private text, patient data,
API request/response bodies, or personal settings.

SelAtRans stores API keys in the macOS login Keychain, scoped to endpoint origin.
Ordinary preferences contain only non-secret options. User text is held in memory
and sent only to the configured HTTPS provider after a deliberate shortcut.
The provider's own retention and processing policies apply to that request.

This public repository does not need API credentials in GitHub Actions. All CI
API tests use a fake in-memory transport and synthetic input.

Local hooks and CI run Gitleaks with redaction. Repository owners should also
keep GitHub secret scanning and push protection enabled when available. Detection
is defense in depth and cannot guarantee discovery of every possible secret.

Report a security vulnerability through GitHub private vulnerability reporting
when available; do not publish exploit details or actual secrets in an issue.
