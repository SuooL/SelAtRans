# SelAtRans

A small native macOS utility for translating selected text into natural English
or Chinese. **Shift–Command–E** translates to English; **Shift–Command–C** to Chinese.
A draggable floating indicator shows status without
adding another menu bar or Dock icon. macOS 13+; Apple Silicon and Intel.

| Source | Result |
| --- | --- |
| Editable selection | Replace only the selection; clipboard stays unchanged. |
| Read-only selection | Copy the translation to the clipboard. |
| No selection | Translate clipboard text and update the clipboard. |
| Window, caret, selection, or text changed while waiting | Preserve the field; copy the translation and show status. |

Translations stream into a nonactivating preview. Left-click the indicator to
show/hide preview and status, drag to move it, and right-click for
settings, pause/resume, or quit. Relaunch the application to reopen settings.
The expanded preview follows the icon, fits short text, and grows with streamed
output until its screen-aware height cap; longer output scrolls. Its rounded
corners have no rectangular background in either appearance.
Only a complete, validated response is written to a field or clipboard. A partial
response remains visibly incomplete and cannot be copied from the preview.

## Install and configure

Download the DMG from [Releases](https://github.com/SuooL/SelAtRans/releases),
drag SelAtRans into Applications, and launch it. Maintainer builds/releases use a
stable Apple Development certificate. Developer ID signing and notarization are
not configured.

1. Add an LLM profile in settings. Profiles support add, edit, delete, test, and
   explicit activation. DeepSeek is the initial profile; multiple profiles may
   use the same provider with different models, effort levels, or credentials.
2. Fill in an HTTPS OpenAI-compatible base URL, model, effort, and API key. Click
   **Save and activate**. Keys are stored as plaintext files in
   `~/Library/Application Support/SelAtRans/Credentials`, isolated by profile and
   endpoint origin. The directory is mode 0700 and files are mode 0600; keys never
   enter preferences or this repository. Upgrading from 0.1.1 requires entering
   each API key once again: legacy Keychain entries are never accessed or deleted.
3. In **Shortcut and updates**, grant Accessibility permission in macOS System
   Settings. Permission is used to capture and safely replace selected text.
4. Select text in another app and press **⇧⌘E** or **⇧⌘C**. Both shortcuts can be changed in
   settings if another app reserves it.
   If the app cannot confirm the current selection, it stops instead of using
   old clipboard text. After manually copying, use **Translate clipboard to
   English/Chinese** from the indicator's right-click menu.

DeepSeek's documented model IDs include `deepseek-flash` and `deepseek-v4-pro`.
Its effort settings are service default, `none`, `low`, `high`, and `max`.
Generic compatible endpoints additionally offer `minimal`, `medium`, and
`xhigh`; supported levels depend on the selected provider/model. Service default
omits the parameter. [DeepSeek API reference](https://api-docs.deepseek.com/api/create-chat-completion/)

The connection-test button sends only a fixed synthetic greeting; it does not
save or activate configuration. Translation sends only the current source text
and translation instruction. There is no clipboard watcher or saved translation
history. Only the latest translation is retained in memory for the preview.

## Build and verify

Requires macOS Command Line Tools, Python 3, and network access for the exact-version
Sparkle dependency and checksum-pinned Gitleaks scanner. Full Xcode is optional
for compilation. Local app packaging needs a stable signing identity in Keychain
(Xcode's free Personal Team Apple Development identity is supported); CI produces
ad-hoc staging artifacts that must be signed locally before publication.

```sh
git clone https://github.com/SuooL/SelAtRans.git
cd SelAtRans
git config core.hooksPath .githooks
scripts/check.sh
scripts/secret-scan.sh --history
open build/package/SelAtRans.app
```

`scripts/package-release.sh` produces a universal `.app`, ZIP, DMG, and checksums.
The core executable checks use an in-memory mock transport and synthetic keys;
CI never needs LLM credentials.

Accessibility varies by application. If a selection cannot be safely replaced,
the utility copies its translation instead of issuing a blind paste. If a surface
does not expose selection or an enabled Copy action, manually copy first and use
the shortcut. A temporary Copy probe preserves prior clipboard representations;
large/image/file clipboards skip that probe to bound memory. Unexposed editor
selections may require manual copy. Password/secure input is not read.

Automatic updates use Sparkle and a signed static appcast hosted with GitHub
Releases. Scheduled checks run daily and can be disabled; installation requires
user action. No user text or API credentials are included in update checks.

Development uses `feature/*` / `hotfix/*` → PR → default **dev** → release PR →
**main**, with required CI and auto-merge. Merged temporary branches are removed.
Agent co-authors are selected automatically for Codex, Claude, or DeepSeek.

- [Requirements and acceptance checks](docs/REQUIREMENTS.md)
- [Development and attribution](docs/DEVELOPMENT.md)
- [Versioning and signed releases](docs/RELEASING.md)
- [Resource use and verification limits](docs/PERFORMANCE.md)
- [Security](SECURITY.md)
